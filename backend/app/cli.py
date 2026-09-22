"""Server buyruqlari.

    python -m app.cli create-admin --email admin@mentorai.uz --password "..." --name "Ali Valiyev"
"""

import argparse
import asyncio
import getpass

from sqlalchemy import select

from app.core.security import hash_password
from app.db.session import get_sessionmaker
from app.models import Role, User
from app.services.plans import seed_plans


async def create_admin(email: str, password: str, name: str) -> None:
    first, _, last = name.partition(" ")
    async with get_sessionmaker()() as db:
        await seed_plans(db)
        user = await db.scalar(select(User).where(User.email == email.lower()))
        if user is None:
            user = User(email=email.lower(), role=Role.ADMIN, first_name=first or "Admin", last_name=last or "")
            db.add(user)
        elif user.role != Role.ADMIN:
            raise SystemExit(f"{email} — admin emas ({user.role}). Boshqa email ishlating.")
        user.password_hash = hash_password(password)
        await db.commit()
    print(f"Admin tayyor: {email}")


def main() -> None:
    parser = argparse.ArgumentParser(prog="python -m app.cli")
    sub = parser.add_subparsers(dest="cmd", required=True)
    ca = sub.add_parser("create-admin", help="Admin yaratish yoki parolini yangilash")
    ca.add_argument("--email", required=True)
    ca.add_argument("--password", help="Berilmasa so'raladi (terminal tarixida qolmaydi)")
    ca.add_argument("--name", default="Admin")
    args = parser.parse_args()
    if args.cmd == "create-admin":
        password = args.password or getpass.getpass("Parol: ")
        if len(password) < 8:
            raise SystemExit("Parol kamida 8 belgi bo'lsin")
        asyncio.run(create_admin(args.email, password, args.name))


if __name__ == "__main__":
    main()
