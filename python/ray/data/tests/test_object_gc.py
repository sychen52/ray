import time

import pytest

import ray
from ray.tests.conftest import *  # noqa

from ray.internal.internal_api import memory_summary


def check_no_spill(ctx, pipe, prefetch_blocks: int = 0):
    # Run .iter_batches() for 10 secs, and we expect no object spilling.
    end_time = time.time() + 10
    for batch in pipe.iter_batches(prefetch_blocks=prefetch_blocks):
        if time.time() > end_time:
            break
    meminfo = memory_summary(ctx.address_info["address"], stats_only=True)
    assert "Spilled" not in meminfo, meminfo


def test_iter_batches_no_spilling_upon_no_transformation(shutdown_only):
    # The object store is about 300MB.
    ctx = ray.init(num_cpus=1, object_store_memory=300e6)
    # The size of dataset is 500*(80*80*4)*8B, about 100MB.
    ds = ray.data.range_tensor(500, shape=(80, 80, 4), parallelism=100)

    check_no_spill(ctx, ds.repeat())
    check_no_spill(ctx, ds.repeat(), 5)

    check_no_spill(ctx, ds.window(blocks_per_window=20))
    check_no_spill(ctx, ds.window(blocks_per_window=20), 5)


def test_iter_batches_no_spilling_upon_prior_transformation(shutdown_only):
    # The object store is about 500MB.
    ctx = ray.init(num_cpus=1, object_store_memory=500e6)
    # The size of dataset is 500*(80*80*4)*8B, about 100MB.
    ds = ray.data.range_tensor(500, shape=(80, 80, 4), parallelism=100)

    # Repeat, with transformation prior to the pipeline.
    check_no_spill(ctx, ds.map_batches(lambda x: x).repeat())
    check_no_spill(ctx, ds.map_batches(lambda x: x).repeat(), 5)

    # Window, with transformation prior to the pipeline.
    check_no_spill(ctx, ds.map_batches(lambda x: x).window(blocks_per_window=20))
    check_no_spill(ctx, ds.map_batches(lambda x: x).window(blocks_per_window=20), 5)


def test_iter_batches_no_spilling_upon_post_transformation(shutdown_only):
    # The object store is about 500MB.
    ctx = ray.init(num_cpus=1, object_store_memory=500e6)
    # The size of dataset is 500*(80*80*4)*8B, about 100MB.
    ds = ray.data.range_tensor(500, shape=(80, 80, 4), parallelism=100)

    # Repeat, with transformation post the pipeline creation.
    check_no_spill(ctx, ds.repeat().map_batches(lambda x: x))
    check_no_spill(ctx, ds.repeat().map_batches(lambda x: x), 5)

    # Window, with transformation post the pipeline creation.
    check_no_spill(ctx, ds.window(blocks_per_window=20).map_batches(lambda x: x))
    check_no_spill(ctx, ds.window(blocks_per_window=20).map_batches(lambda x: x), 5)


def test_iter_batches_no_spilling_upon_transformations(shutdown_only):
    # The object store is about 700MB.
    ctx = ray.init(num_cpus=1, object_store_memory=700e6)
    # The size of dataset is 500*(80*80*4)*8B, about 100MB.
    ds = ray.data.range_tensor(500, shape=(80, 80, 4), parallelism=100)

    # Repeat, with transformation before and post the pipeline.
    check_no_spill(ctx, ds.map_batches(lambda x: x).repeat().map_batches(lambda x: x))
    check_no_spill(
        ctx, ds.map_batches(lambda x: x).repeat().map_batches(lambda x: x), 5
    )

    # Window, with transformation before and post the pipeline.
    check_no_spill(
        ctx,
        ds.map_batches(lambda x: x)
        .window(blocks_per_window=20)
        .map_batches(lambda x: x),
    )
    check_no_spill(
        ctx,
        ds.map_batches(lambda x: x)
        .window(blocks_per_window=20)
        .map_batches(lambda x: x),
        5,
    )


def test_iter_batches_no_spilling_upon_shuffle(shutdown_only):
    # The object store is about 500MB.
    ctx = ray.init(num_cpus=1, object_store_memory=500e6)
    # The size of dataset is 500*(80*80*4)*8B, about 100MB.
    ds = ray.data.range_tensor(500, shape=(80, 80, 4), parallelism=100)

    check_no_spill(ctx, ds.repeat().random_shuffle_each_window())
    check_no_spill(ctx, ds.repeat().random_shuffle_each_window(), 5)

    check_no_spill(ctx, ds.window(blocks_per_window=20).random_shuffle_each_window())
    check_no_spill(ctx, ds.window(blocks_per_window=20).random_shuffle_each_window(), 5)


if __name__ == "__main__":
    import sys

    sys.exit(pytest.main(["-v", __file__]))
