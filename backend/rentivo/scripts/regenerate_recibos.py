"""List all PAID bills and enqueue a `recibo.render` job for each one.

Usage:
    python -m rentivo.scripts.regenerate_recibos
    python -m rentivo.scripts.regenerate_recibos --dry-run

Behavior:
- Walks every billing and every bill, keeping only bills in the PAID status
  (a recibo — "Recibo de Pagamento" — exists only for a paid bill).
- For every paid bill, enqueues a single ``recibo.render`` job and prints the
  resulting ULID. The render job re-checks ``status == PAID`` before writing,
  so this is idempotent: re-running overwrites the same stored object and a
  bill that left PAID in the meantime is skipped by the worker.
- Unlike ``regenerate_pdfs``, there is no PIX pre-flight: the recibo issuer
  falls back to the billing name when PIX is absent, so a paid bill always
  renders successfully (it would never dead-letter for missing PIX).
- Prints a final summary: how many were enqueued, plus how many
  ``recibo.render`` jobs are still pending or running. The script does NOT
  wait for the worker to drain.

This is the backfill for bills that were already PAID before stored recibos
existed: their ``recibo_pdf_path`` is NULL, so this enqueues a render for each.
"""

from __future__ import annotations

from rich.console import Console
from rich.table import Table
from ulid import ULID

from rentivo.jobs.factory import get_job_backend
from rentivo.models import format_brl
from rentivo.models.bill import BillStatus
from rentivo.repositories.factory import (
    get_audit_log_repository,
    get_bill_repository,
    get_billing_repository,
    get_job_repository,
)
from rentivo.scripts._cli import boot, collect_bills, parse_dry_run
from rentivo.services.audit_service import AuditService
from rentivo.services.job_service import JobService

console = Console()


def main() -> None:
    conn = boot()
    dry_run = parse_dry_run()

    billing_repo = get_billing_repository()
    bill_repo = get_bill_repository()
    audit_repo = get_audit_log_repository()
    job_repo = get_job_repository()

    audit_service = AuditService(audit_repo)
    job_service = JobService(get_job_backend(conn), audit_service)

    billings, paid_bills = collect_bills(
        billing_repo,
        bill_repo,
        keep=lambda bill: bill.status == BillStatus.PAID.value,
    )

    if not billings:
        console.print("[yellow]Nenhuma cobranca encontrada.[/yellow]")
        return

    if not paid_bills:
        console.print("[yellow]Nenhuma fatura paga encontrada.[/yellow]")
        return

    table = Table(title="Faturas pagas")
    table.add_column("#", style="dim")
    table.add_column("Cobranca", style="bold")
    table.add_column("Referencia")
    table.add_column("Total", justify="right")
    table.add_column("Recibo", style="dim")

    for billing, bill in paid_bills:
        recibo_status = "armazenado" if bill.recibo_pdf_path else "pendente"
        table.add_row(
            str(bill.id),
            billing.name,
            bill.reference_month,
            format_brl(bill.total_amount),
            recibo_status,
        )

    console.print(table)
    console.print(f"\nTotal de faturas pagas: [bold]{len(paid_bills)}[/bold]")

    if dry_run:
        console.print("\n[yellow]--dry-run: nenhum recibo foi enfileirado.[/yellow]")
        return

    console.print("\n[cyan]Enfileirando jobs recibo.render...[/cyan]\n")

    enqueued = 0
    for billing, bill in paid_bills:
        # Mint the render operation id here, exactly as BillService does when a
        # bill transitions to PAID. Without it the handler falls back to the
        # persistent job identity, so this script was the last producer keeping
        # that legacy path reachable.
        render_operation_id = str(ULID())
        job = job_service.enqueue(
            "recibo.render",
            {"bill_id": bill.id, "render_operation_id": render_operation_id},
            source="cli",
            max_attempts=3,
        )
        enqueued += 1
        console.print(f"  [green]✓[/green] {billing.name} - {bill.reference_month} → enqueued ulid={job.ulid}")

    pending_or_running = job_repo.count_by_type_and_statuses("recibo.render", ("pending", "running"))
    console.print(f"\n[green bold]{enqueued} recibo(s) enfileirado(s) com sucesso![/green bold]")
    console.print(f"[dim]{pending_or_running} job(s) recibo.render aguardando o worker (pending+running).[/dim]")


if __name__ == "__main__":  # pragma: no cover
    main()
