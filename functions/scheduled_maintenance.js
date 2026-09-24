'use strict';

/**
 * Runs every maintenance task even when an earlier task fails, then surfaces
 * the combined failure so Cloud Scheduler still records an unhealthy run.
 * Tasks are sequential by default. Independent tasks may opt into concurrent
 * execution when combining their former runtimes could exceed one timeout.
 */
async function runMaintenanceTasks(
  label,
  tasks,
  onError = () => undefined,
  {concurrent = false} = {}
) {
  const failures = [];
  if (concurrent) {
    const results = await Promise.allSettled(tasks.map((task) => task.run()));
    results.forEach((result, index) => {
      if (result.status !== 'rejected') return;
      failures.push(result.reason);
      onError(tasks[index].name, result.reason);
    });
  } else {
    for (const task of tasks) {
      try {
        await task.run();
      } catch (error) {
        failures.push(error);
        onError(task.name, error);
      }
    }
  }
  if (failures.length > 0) {
    throw new AggregateError(
      failures,
      `${label} failed in ${failures.length} maintenance task(s).`
    );
  }
}

module.exports = {runMaintenanceTasks};
