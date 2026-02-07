from landlord.cli.app import main_menu
from landlord.db import initialize_db


def main() -> None:
    initialize_db()
    main_menu()


if __name__ == "__main__":
    main()
