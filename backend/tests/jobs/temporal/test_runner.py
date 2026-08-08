from temporalio import activity, workflow

from rentivo.jobs.temporal import activities, runner, workflows
from rentivo.jobs.temporal.registry import JOB_WORKFLOWS


def test_worker_components_lists_all_workflows_and_activities():
    wfs, acts = runner.worker_components()
    assert set(wfs) == {
        workflows.EmailSendWorkflow,
        workflows.CommunicationSendWorkflow,
        workflows.PdfRenderWorkflow,
        workflows.ReciboRenderWorkflow,
        workflows.S3DeleteWorkflow,
        workflows.ExportGenerateWorkflow,
        workflows.ExportSendWorkflow,
        workflows.AuthCleanupWorkflow,
    }
    assert set(acts) == {
        *activities.ACTIVITY_BY_JOB_TYPE.values(),
        activities.finalize_job_activity,
    }


def test_registered_names_match_the_registration_table():
    """Workflow and activity names live in Temporal history: they must stay
    byte-identical to the table, whatever the generation mechanics are."""
    wfs, _ = runner.worker_components()
    assert [workflow._Definition.must_from_class(wf).name for wf in wfs] == [
        workflow_name for _, workflow_name in JOB_WORKFLOWS
    ]
    assert [
        activity._Definition.must_from_callable(activities.ACTIVITY_BY_JOB_TYPE[job_type]).name
        for job_type, _ in JOB_WORKFLOWS
    ] == [job_type for job_type, _ in JOB_WORKFLOWS]
