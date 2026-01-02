from sqlalchemy.orm import declarative_base

Base = declarative_base()

# Models are imported in main.py to avoid circular imports
# Alembic will discover them through Base.metadata
