from __future__ import annotations

# The canonical Temporal registration table: one row per job type, paired with
# the workflow type name it runs under.
#
# Both names are protocol, not implementation detail. The workflow name and the
# activity name (which is the job type verbatim) are written into Temporal
# workflow history, so a running or scheduled workflow keeps referring to the
# name it was started with. They are therefore spelled out here instead of being
# derived from the job type: renaming either one strands in-flight work.
#
# Everything else — the workflow classes, the per-job-type activities, the
# worker registration lists, and the enqueue-side job-type-to-workflow map — is
# derived from this table, so adding a job type means adding one row.
JOB_WORKFLOWS: tuple[tuple[str, str], ...] = (
    ("email.send", "EmailSendWorkflow"),
    ("communication.send", "CommunicationSendWorkflow"),
    ("pdf.render", "PdfRenderWorkflow"),
    ("recibo.render", "ReciboRenderWorkflow"),
    ("s3.delete", "S3DeleteWorkflow"),
    ("export.generate", "ExportGenerateWorkflow"),
    ("export.send", "ExportSendWorkflow"),
    ("auth.cleanup", "AuthCleanupWorkflow"),
)

JOB_TYPES: tuple[str, ...] = tuple(job_type for job_type, _ in JOB_WORKFLOWS)
