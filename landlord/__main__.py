from landlord.cli.app import main_menu
from landlord.db import initialize_db
from landlord.logging import configure_logging


def main() -> None:
    configure_logging()
    initialize_db()
    main_menu()


if __name__ == "__main__":
    main()
