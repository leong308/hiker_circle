// orderedCheckpointMatches aligns checkpoint animation positions with route traversal order,
// including repeated coordinates.
/// Minimum-distance matching constrained to traversal order, with anchored ends.
List<int> orderedCheckpointMatches(List<List<double>> costs) {
  if (costs.isEmpty || costs.first.isEmpty) return [];
  final n = costs.first.length;
  if (costs.length == 1) return [0];
  var previous = List<double>.filled(n, double.infinity)..[0] = costs[0][0];
  final parents = <List<int>>[];
  for (var c = 1; c < costs.length; c++) {
    final current = List<double>.filled(n, double.infinity);
    final parent = List<int>.filled(n, 0);
    var best = double.infinity;
    var bestIndex = 0;
    for (var j = 0; j < n; j++) {
      final candidate = n >= costs.length ? j - 1 : j;
      if (candidate >= 0 && previous[candidate] < best) {
        best = previous[candidate];
        bestIndex = candidate;
      }
      current[j] = best + costs[c][j];
      parent[j] = bestIndex;
    }
    parents.add(parent);
    previous = current;
  }
  final result = List<int>.filled(costs.length, 0);
  result[result.length - 1] = n - 1;
  for (var c = result.length - 1; c > 0; c--) {
    result[c - 1] = parents[c - 1][result[c]];
  }
  return result;
}

/// Bound the tail by physical distance, not by the density of route vertices.
int cometTailStart(List<double> distances, int head, double length) {
  var start = head;
  final cutoff = distances[head] - length;
  while (start > 0 && distances[start - 1] >= cutoff) {
    start--;
  }
  return start == head && head > 0 ? head - 1 : start;
}
