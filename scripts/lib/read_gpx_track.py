"""Read exported GPX without simplifying, rerouting, or dropping track points."""
import json
import sys
import xml.etree.ElementTree as ET


def read_gpx(path):
    root = ET.parse(path).getroot()
    def local(node):
        return node.tag.rsplit('}', 1)[-1]
    def child_text(node, name):
        return next((c.text for c in node if local(c) == name), None)
    def point(node):
        result = {'lat': float(node.attrib['lat']), 'lon': float(node.attrib['lon'])}
        ele = child_text(node, 'ele')
        if ele is not None:
            result['ele'] = float(ele)
        name = child_text(node, 'name')
        if name:
            result['name'] = name
        return result
    segments = [[point(p) for p in s if local(p) == 'trkpt']
                for s in root.iter() if local(s) == 'trkseg']
    if len(segments) != 1 or len(segments[0]) < 2:
        raise ValueError('Use a GPX Track export containing exactly one connected track segment.')
    names = [child_text(t, 'name') for t in root if local(t) == 'trk']
    return {'name': next((n for n in names if n), ''), 'points': segments[0],
            'waypoints': [point(w) for w in root if local(w) == 'wpt']}

if __name__ == '__main__':
    print(json.dumps(read_gpx(sys.argv[1]), allow_nan=False))
