import unittest

import ray
import ray.rllib.algorithms.appo as appo
from ray.rllib.policy.sample_batch import DEFAULT_POLICY_ID
from ray.rllib.utils.metrics.learner_info import LEARNER_INFO, LEARNER_STATS_KEY
from ray.rllib.utils.test_utils import (
    check_compute_single_action,
    check_train_results,
    framework_iterator,
)


class TestAPPO(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        ray.init()

    @classmethod
    def tearDownClass(cls):
        ray.shutdown()

    def test_appo_compilation(self):
        """Test whether APPO can be built with both frameworks."""
        config = appo.APPOConfig().rollouts(num_rollout_workers=1)
        num_iterations = 2

        for _ in framework_iterator(config, with_eager_tracing=True):
            print("w/o v-trace")
            config.vtrace = False
            trainer = config.build(env="CartPole-v0")
            for i in range(num_iterations):
                results = trainer.train()
                check_train_results(results)
                print(results)
            check_compute_single_action(trainer)
            trainer.stop()

            print("w/ v-trace")
            config.vtrace = True
            trainer = config.build(env="CartPole-v0")
            for i in range(num_iterations):
                results = trainer.train()
                check_train_results(results)
                print(results)
            check_compute_single_action(trainer)
            trainer.stop()

    def test_appo_compilation_use_kl_loss(self):
        """Test whether APPO can be built with kl_loss enabled."""
        config = (
            appo.APPOConfig().rollouts(num_rollout_workers=1).training(use_kl_loss=True)
        )
        num_iterations = 2

        for _ in framework_iterator(config, with_eager_tracing=True):
            trainer = config.build(env="CartPole-v0")
            for i in range(num_iterations):
                results = trainer.train()
                check_train_results(results)
                print(results)
            check_compute_single_action(trainer)
            trainer.stop()

    def test_appo_two_tf_optimizers(self):
        # Not explicitly setting this should cause a warning, but not fail.
        # config["_tf_policy_handles_more_than_one_loss"] = True
        config = (
            appo.APPOConfig()
            .rollouts(num_rollout_workers=1)
            .training(_separate_vf_optimizer=True, _lr_vf=0.002)
        )
        # Make sure we have two completely separate models for policy and
        # value function.
        config.model["vf_share_layers"] = False

        num_iterations = 2

        # Only supported for tf so far.
        for _ in framework_iterator(config, frameworks=("tf2", "tf")):
            trainer = config.build(env="CartPole-v0")
            for i in range(num_iterations):
                results = trainer.train()
                check_train_results(results)
                print(results)
            check_compute_single_action(trainer)
            trainer.stop()

    def test_appo_entropy_coeff_schedule(self):
        # Initial lr, doesn't really matter because of the schedule below.
        config = (
            appo.APPOConfig()
            .rollouts(
                num_rollout_workers=1,
                batch_mode="truncate_episodes",
                rollout_fragment_length=10,
            )
            .resources(num_gpus=0)
            .training(
                train_batch_size=20,
                entropy_coeff=0.01,
                entropy_coeff_schedule=[
                    [0, 0.1],
                    [100, 0.01],
                    [300, 0.001],
                    [500, 0.0001],
                ],
            )
        )

        config.min_sample_timesteps_per_iteration = 20
        # 0 metrics reporting delay, this makes sure timestep,
        # which entropy coeff depends on, is updated after each worker rollout.
        config.min_time_s_per_iteration = 0

        def _step_n_times(trainer, n: int):
            """Step trainer n times.

            Returns:
                learning rate at the end of the execution.
            """
            for _ in range(n):
                results = trainer.train()
                print(trainer.workers.local_worker().global_vars)
                print(results)
            return results["info"][LEARNER_INFO][DEFAULT_POLICY_ID][LEARNER_STATS_KEY][
                "entropy_coeff"
            ]

        for _ in framework_iterator(config):
            trainer = config.build(env="CartPole-v0")

            coeff = _step_n_times(trainer, 10)  # 200 timesteps
            # Should be close to the starting coeff of 0.01.
            self.assertLessEqual(coeff, 0.01)
            self.assertGreaterEqual(coeff, 0.001)

            coeff = _step_n_times(trainer, 20)  # 400 timesteps
            # Should have annealed to the final coeff of 0.0001.
            self.assertLessEqual(coeff, 0.001)

            trainer.stop()


if __name__ == "__main__":
    import pytest
    import sys

    sys.exit(pytest.main(["-v", __file__]))
