#!/usr/bin/env python3
import bencodepy
import sys
import json

if len(sys.argv) < 2:
    print("Usage: dumptorrent <torrent_file>")
    sys.exit(1)

try:
    with open(sys.argv[1], 'rb') as f:
        torrent_data = bencodepy.decode(f.read())
    
    def decode_bytes(obj):
        if isinstance(obj, bytes):
            try:
                return obj.decode('utf-8')
            except:
                return obj.hex()
        elif isinstance(obj, dict):
            return {decode_bytes(k): decode_bytes(v) for k, v in obj.items()}
        elif isinstance(obj, list):
            return [decode_bytes(i) for i in obj]
        return obj
    
    result = decode_bytes(torrent_data)
    print(json.dumps(result, indent=2))
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
