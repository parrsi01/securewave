import random
from typing import Optional


def seed_everything(seed: int, numpy_seed: Optional[int] = None) -> None:
    """Seed Python and optional NumPy RNGs."""
    random.seed(seed)
    try:
        import numpy as np
        np.random.seed(numpy_seed if numpy_seed is not None else seed)
    except Exception:
        return
