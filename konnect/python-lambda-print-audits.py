import os
import logging
import time
import base64
import gzip
import zlib
import json
import re
from flask import Flask, request
import requests
from nacl.signing import VerifyKey
from nacl.exceptions import BadSignatureError

app = Flask(__name__)

# Configuration
host = os.getenv('HOST', '0.0.0.0')
port = int(os.getenv('PORT', 8080))
jwks_endpoint = os.getenv('JWKS_ENDPOINT', 'https://us.api.konghq.com/v2/audit-log-webhook/jwks.json')
jwks = os.getenv('JWKS')
cache_ttl = int(os.getenv('CACHE_TTL', 10))

# Logging configuration
logging.basicConfig(
    level=getattr(logging, os.getenv('LOG_LEVEL', 'INFO').upper(), logging.INFO),
    format='%(asctime)s [%(levelname)s]: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger()

# Cached public keys
keys_cache = {'data': [], 'last_updated': None}

def fetch_public_keys():
    if jwks:
        jwks_data = json.loads(jwks) if isinstance(jwks, str) else jwks
        return [{'bytes': base64.urlsafe_b64decode(jwk['x'] + '==')} for jwk in jwks_data['keys']]
    
    current_time = time.time()
    if not keys_cache['data'] or (current_time - keys_cache['last_updated']) / 60 > cache_ttl:
        try:
            response = requests.get(jwks_endpoint)
            response.raise_for_status()
            keys_cache['data'] = [{'bytes': base64.urlsafe_b64decode(jwk['x'] + '==')} for jwk in response.json()['keys']]
            keys_cache['last_updated'] = current_time
        except Exception as e:
            logger.error(f'Error fetching public keys: {e}')
            raise
    return keys_cache['data']

def strip_signature_field(input_str, is_json):
    sig_match = r',\s*"sig":"([^"]*)"' if is_json else 'sig=([^\\s]*)'
    sig_value = re.search(sig_match, input_str)
    return (re.sub(sig_match, '', input_str).strip(), sig_value.group(1).strip()) if sig_value else (input_str, None)

def validate_signature(input_str, public_key_bytes, is_json):
    modified_str, sig_value = strip_signature_field(input_str, is_json)
    if not sig_value:
        return False
    try:
        VerifyKey(public_key_bytes).verify(modified_str.encode(), base64.urlsafe_b64decode(sig_value + '=='))
        return True
    except BadSignatureError:
        return False

@app.route('/audits', methods=['POST'])
def handle_audit_logs():
    content_encoding = request.headers.get('Content-Encoding', '').lower()
    try:
        if content_encoding == 'gzip':
            body = gzip.decompress(request.data).decode('utf-8')
        elif content_encoding == 'deflate':
            body = zlib.decompress(request.data).decode('utf-8')
        else:
            body = request.data.decode('utf-8')
    except Exception as e:
        logger.error(f'Failed to process data: {e}')
        return 'Invalid data', 400

    try:
        keys = fetch_public_keys()
    except Exception as e:
        logger.error(f'Error fetching public keys: {e}')
        return 'Error fetching public keys', 500

    valid_logs = []
    is_json = body.startswith('{')
    for log_line in body.splitlines():
        is_json = log_line.startswith('{')
        if validate_signature(log_line, keys[0]['bytes'], is_json):
            valid_logs.append(json.loads(log_line) if is_json else log_line)
        else:
            logger.error('Signature verification failed for a log line')

    if valid_logs:
        print("\n".join(json.dumps(obj, separators=(',', ':')) for obj in valid_logs) if is_json else '\n'.join(valid_logs))
    else:
        logger.warning('No valid audit logs found')
    return 'Audits received', 200

if __name__ == '__main__':
    try:
        jwks = json.loads(os.getenv('JWKS'))
        logger.info('Using JWKS provided as an environment variable')
    except Exception:
        logger.warning('JWKS not provided, using JWKS endpoint instead:')
        logger.info(jwks_endpoint)
    app.run(host=host, port=port)