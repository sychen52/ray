from typing import Optional, TYPE_CHECKING

from tensorflow import keras

from ray.air.checkpoint import Checkpoint
from ray.air.constants import MODEL_KEY, PREPROCESSOR_KEY

if TYPE_CHECKING:
    from ray.data.preprocessor import Preprocessor


def to_air_checkpoint(
    model: keras.Model, preprocessor: Optional["Preprocessor"] = None
) -> Checkpoint:
    """Convert a pretrained model to AIR checkpoint for serve or inference.

    Args:
        model: A pretrained model.
        preprocessor: A fitted preprocessor. The preprocessing logic will
            be applied to serve/inference.
    Returns:
        A Ray Air checkpoint.
    """
    checkpoint = Checkpoint.from_dict(
        {PREPROCESSOR_KEY: preprocessor, MODEL_KEY: model.get_weights()}
    )
    return checkpoint
