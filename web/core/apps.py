import os

from django.apps import AppConfig


class CoreConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "core"

    def ready(self):
        from landlord.db import initialize_db

        # Alembic config uses relative paths from the project root
        project_root = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
        saved_cwd = os.getcwd()
        try:
            os.chdir(project_root)
            initialize_db()
        finally:
            os.chdir(saved_cwd)
