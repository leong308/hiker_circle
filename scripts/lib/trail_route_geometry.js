/* eslint-disable no-console */
'use strict';

const PRIMARY_ROUTE_ROLES = new Set(['', 'forward', 'backward', 'reverse']);

function haversine(a, b) {
  const radians = (degrees) => degrees * Math.PI / 180;
  const dLat = radians(b.lat - a.lat);
  const dLon = radians(b.lon - a.lon);
  const lat1 = radians(a.lat);
  const lat2 = radians(b.lat);
  const sinLat = Math.sin(dLat / 2);
  const sinLon = Math.sin(dLon / 2);
  const value = sinLat * sinLat +
    Math.cos(lat1) * Math.cos(lat2) * sinLon * sinLon;
  return 6371000 * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value));
}

function routeDistanceMeters(points) {
  let result = 0;
  for (let index = 1; index < points.length; index += 1) {
    result += haversine(points[index - 1], points[index]);
  }
  return result;
}

function maxSegmentDistanceMeters(points) {
  let result = 0;
  for (let index = 1; index < points.length; index += 1) {
    result = Math.max(result, haversine(points[index - 1], points[index]));
  }
  return result;
}

function relationParts(data, relationId) {
  const elements = data && data.elements || [];
  const relation = elements.find(
    (element) => element.type === 'relation' && element.id === relationId,
  );
  if (!relation) throw new Error(`OSM relation ${relationId} was not found.`);
  if (relation.tags && relation.tags.route !== 'hiking') {
    throw new Error(`OSM relation ${relationId} is not tagged as a hiking route.`);
  }
  return {
    relation,
    nodesById: new Map(
      elements.filter((element) => element.type === 'node')
        .map((node) => [node.id, node]),
    ),
    waysById: new Map(
      elements.filter((element) => element.type === 'way')
        .map((way) => [way.id, way]),
    ),
  };
}

function primaryMembers(relation) {
  const allWays = (relation.members || []).filter((member) => member.type === 'way');
  return {
    included: allWays.filter((member) => PRIMARY_ROUTE_ROLES.has(member.role || '')),
    excluded: allWays.filter((member) => !PRIMARY_ROUTE_ROLES.has(member.role || '')),
  };
}

function wayNodeIds(way) {
  if (!way || !Array.isArray(way.nodes)) return [];
  return way.nodes.filter((nodeId) => Number.isInteger(nodeId));
}

function pointForNode(nodesById, nodeId) {
  const node = nodesById.get(nodeId);
  if (!node || !Number.isFinite(node.lat) || !Number.isFinite(node.lon)) {
    throw new Error(`OSM node ${nodeId} has no usable coordinate.`);
  }
  return { lat: node.lat, lon: node.lon };
}

function appendDistinct(result, points) {
  for (const point of points) {
    const previous = result[result.length - 1];
    if (!previous || haversine(previous, point) > 0.5) result.push(point);
  }
}

function closestNodeId(candidateIds, nodesById, hint) {
  let closest = null;
  for (const nodeId of candidateIds) {
    const distance = haversine(hint, pointForNode(nodesById, nodeId));
    if (!closest || distance < closest.distance) closest = { nodeId, distance };
  }
  return closest;
}

function orderedEulerEdges(edges, startNode) {
  const adjacency = new Map();
  for (const edge of edges) {
    if (!adjacency.has(edge.a)) adjacency.set(edge.a, []);
    if (!adjacency.has(edge.b)) adjacency.set(edge.b, []);
    adjacency.get(edge.a).push(edge.index);
    adjacency.get(edge.b).push(edge.index);
  }

  // Relation member order is retained inside each adjacency list. Hierholzer's
  // traversal then preserves author intent while guaranteeing every transition
  // shares a real OSM endpoint.
  const cursor = new Map();
  const used = new Set();
  const stack = [{ node: startNode, edgeIndex: null, from: null }];
  const reversed = [];
  while (stack.length > 0) {
    const top = stack[stack.length - 1];
    const candidates = adjacency.get(top.node) || [];
    let offset = cursor.get(top.node) || 0;
    while (offset < candidates.length && used.has(candidates[offset])) offset += 1;
    cursor.set(top.node, offset + 1);
    if (offset < candidates.length) {
      const edgeIndex = candidates[offset];
      used.add(edgeIndex);
      const edge = edges[edgeIndex];
      const nextNode = edge.a === top.node ? edge.b : edge.a;
      stack.push({ node: nextNode, edgeIndex, from: top.node });
    } else {
      const finished = stack.pop();
      if (finished.edgeIndex != null) {
        reversed.push({
          edgeIndex: finished.edgeIndex,
          from: finished.from,
          to: finished.node,
        });
      }
    }
  }
  if (used.size !== edges.length) {
    throw new Error(
      `Primary hiking members are disconnected (${used.size}/${edges.length} connected).`,
    );
  }
  return reversed.reverse();
}

function assemblePrimaryRelation(data, relationId, options = {}) {
  const { relation, nodesById, waysById } = relationParts(data, relationId);
  const { included, excluded } = primaryMembers(relation);
  const edges = included.map((member, index) => {
    const way = waysById.get(member.ref);
    const nodes = wayNodeIds(way);
    if (nodes.length < 2) {
      throw new Error(`OSM way ${member.ref} has incomplete route geometry.`);
    }
    return {
      index,
      member,
      nodes,
      a: nodes[0],
      b: nodes[nodes.length - 1],
    };
  });
  if (edges.length === 0) throw new Error(`OSM relation ${relationId} has no primary ways.`);

  const degrees = new Map();
  for (const edge of edges) {
    degrees.set(edge.a, (degrees.get(edge.a) || 0) + 1);
    degrees.set(edge.b, (degrees.get(edge.b) || 0) + 1);
  }
  const odd = [...degrees.entries()].filter(([, degree]) => degree % 2 === 1)
    .map(([nodeId]) => nodeId);
  if (odd.length !== 0 && odd.length !== 2) {
    throw new Error(
      `Primary hiking route ${relationId} is not a single walkable path (${odd.length} odd endpoints).`,
    );
  }

  const first = edges[0];
  const role = first.member.role || '';
  const memberStart = role === 'backward' || role === 'reverse' ? first.b : first.a;
  const candidates = odd.length === 2 ? odd : [...degrees.keys()];
  const startNode = options.startHint
    ? closestNodeId(candidates, nodesById, options.startHint).nodeId
    : candidates.includes(memberStart) ? memberStart : candidates[0];
  const traversal = orderedEulerEdges(edges, startNode);
  const points = [];
  for (const step of traversal) {
    const edge = edges[step.edgeIndex];
    const nodeIds = step.from === edge.a ? edge.nodes : [...edge.nodes].reverse();
    appendDistinct(points, nodeIds.map((nodeId) => pointForNode(nodesById, nodeId)));
  }
  return {
    points,
    relation,
    includedMemberCount: included.length,
    excludedRoles: excluded.map((member) => member.role || '(empty)'),
  };
}

class MinHeap {
  constructor() {
    this.items = [];
  }

  push(item) {
    this.items.push(item);
    let index = this.items.length - 1;
    while (index > 0) {
      const parent = Math.floor((index - 1) / 2);
      if (this.items[parent].distance <= item.distance) break;
      this.items[index] = this.items[parent];
      index = parent;
    }
    this.items[index] = item;
  }

  pop() {
    if (this.items.length === 0) return null;
    const first = this.items[0];
    const last = this.items.pop();
    if (this.items.length > 0) {
      let index = 0;
      while (true) {
        let child = index * 2 + 1;
        if (child >= this.items.length) break;
        if (child + 1 < this.items.length &&
            this.items[child + 1].distance < this.items[child].distance) child += 1;
        if (this.items[child].distance >= last.distance) break;
        this.items[index] = this.items[child];
        index = child;
      }
      this.items[index] = last;
    }
    return first;
  }
}

function shortestPathInRelation(data, relationId, startHint, endHint, options = {}) {
  const { relation, nodesById, waysById } = relationParts(data, relationId);
  const { included, excluded } = primaryMembers(relation);
  const adjacency = new Map();
  const candidateIds = new Set();
  for (const member of included) {
    const nodes = wayNodeIds(waysById.get(member.ref));
    for (let index = 1; index < nodes.length; index += 1) {
      const a = nodes[index - 1];
      const b = nodes[index];
      const weight = haversine(pointForNode(nodesById, a), pointForNode(nodesById, b));
      candidateIds.add(a);
      candidateIds.add(b);
      if (!adjacency.has(a)) adjacency.set(a, []);
      if (!adjacency.has(b)) adjacency.set(b, []);
      adjacency.get(a).push({ nodeId: b, weight });
      adjacency.get(b).push({ nodeId: a, weight });
    }
  }
  const start = closestNodeId(candidateIds, nodesById, startHint);
  const end = closestNodeId(candidateIds, nodesById, endHint);
  const maxSnapMeters = options.maxSnapMeters || 300;
  if (start.distance > maxSnapMeters || end.distance > maxSnapMeters) {
    throw new Error(
      `Route hints are too far from OSM relation ${relationId} ` +
      `(${start.distance.toFixed(0)}m, ${end.distance.toFixed(0)}m).`,
    );
  }

  const distances = new Map([[start.nodeId, 0]]);
  const previous = new Map();
  const heap = new MinHeap();
  heap.push({ nodeId: start.nodeId, distance: 0 });
  while (heap.items.length > 0) {
    const current = heap.pop();
    if (current.distance !== distances.get(current.nodeId)) continue;
    if (current.nodeId === end.nodeId) break;
    for (const edge of adjacency.get(current.nodeId) || []) {
      const nextDistance = current.distance + edge.weight;
      if (nextDistance < (distances.get(edge.nodeId) ?? Infinity)) {
        distances.set(edge.nodeId, nextDistance);
        previous.set(edge.nodeId, current.nodeId);
        heap.push({ nodeId: edge.nodeId, distance: nextDistance });
      }
    }
  }
  if (!distances.has(end.nodeId)) {
    throw new Error(`No connected hiking path was found in OSM relation ${relationId}.`);
  }
  const nodeIds = [];
  let current = end.nodeId;
  while (current != null) {
    nodeIds.push(current);
    if (current === start.nodeId) break;
    current = previous.get(current);
  }
  nodeIds.reverse();
  return {
    points: nodeIds.map((nodeId) => pointForNode(nodesById, nodeId)),
    relation,
    includedMemberCount: included.length,
    excludedRoles: excluded.map((member) => member.role || '(empty)'),
    startSnapMeters: start.distance,
    endSnapMeters: end.distance,
  };
}

function mirrorOutAndBack(points) {
  if (points.length < 2) return [...points];
  return [...points, ...points.slice(0, -1).reverse()];
}

function pointsFromGeoJsonGeometry(geometry) {
  if (!geometry || !['LineString', 'MultiLineString'].includes(geometry.type)) {
    throw new Error('Hiking route provider returned unsupported geometry.');
  }
  const rawLines = geometry.type === 'LineString'
    ? [geometry.coordinates]
    : geometry.coordinates;
  const result = [];
  for (const rawLine of rawLines) {
    let line = rawLine.filter(
      (coordinate) => Array.isArray(coordinate) &&
        Number.isFinite(coordinate[0]) && Number.isFinite(coordinate[1]),
    ).map((coordinate) => ({ lat: coordinate[1], lon: coordinate[0] }));
    if (line.length === 0) continue;
    if (result.length > 0 &&
        haversine(result[result.length - 1], line[line.length - 1]) <
        haversine(result[result.length - 1], line[0])) {
      line = line.reverse();
    }
    appendDistinct(result, line);
  }
  return result;
}

function validateGeometry(points, routeShape) {
  if (points.length < 3) throw new Error('Route geometry contains fewer than three points.');
  for (const point of points) {
    if (!Number.isFinite(point.lat) || !Number.isFinite(point.lon)) {
      throw new Error('Route geometry contains an invalid coordinate.');
    }
  }
  const distanceMeters = routeDistanceMeters(points);
  if (distanceMeters < 200) throw new Error('Route geometry is implausibly short.');
  const endpointGapMeters = haversine(points[0], points[points.length - 1]);
  if (['loop', 'out-and-back'].includes(routeShape) && endpointGapMeters > 40) {
    throw new Error(
      `${routeShape} route does not return to its trailhead (${endpointGapMeters.toFixed(0)}m gap).`,
    );
  }
  return {
    distanceMeters,
    endpointGapMeters,
    maxSegmentMeters: maxSegmentDistanceMeters(points),
  };
}

module.exports = {
  assemblePrimaryRelation,
  haversine,
  maxSegmentDistanceMeters,
  mirrorOutAndBack,
  pointsFromGeoJsonGeometry,
  routeDistanceMeters,
  shortestPathInRelation,
  validateGeometry,
};
