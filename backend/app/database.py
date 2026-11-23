from typing import Generator
from sqlalchemy import text
from sqlmodel import Session, SQLModel, create_engine
from app.config import settings

connect_args = {"check_same_thread": False} if settings.database_url.startswith("sqlite") else {}
engine = create_engine(settings.database_url, echo=False, connect_args=connect_args)


def init_db() -> None:
    SQLModel.metadata.create_all(engine)
    if settings.database_url.startswith("sqlite"):
        with engine.begin() as conn:
            cols = {
                row[1]
                for row in conn.execute(text("PRAGMA table_info(deal_option_nodes)")).fetchall()
            }
            if cols and "product_url" not in cols:
                conn.execute(
                    text("ALTER TABLE deal_option_nodes ADD COLUMN product_url TEXT DEFAULT ''")
                )


def get_session() -> Generator[Session, None, None]:
    with Session(engine) as session:
        yield session
