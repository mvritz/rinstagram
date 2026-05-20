"""
Unit tests for the encryption module.

Tests run against the pure function directly — no HTTP overhead required.
"""

import base64
import struct

import pytest
from nacl.public import PrivateKey, SealedBox
from Cryptodome.Cipher import AES

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.encryption import encrypt_instagram_password


def make_test_keypair():
    """Generate a throw-away NaCl key pair for testing."""
    private_key = PrivateKey.generate()
    public_key  = private_key.public_key
    pub_hex     = public_key.encode().hex()
    return private_key, pub_hex


class TestEncryptInstagramPassword:
    def test_returns_base64_string(self):
        _, pub_hex = make_test_keypair()
        result = encrypt_instagram_password("123", pub_hex, "password")
        assert isinstance(result, str)
        decoded = base64.b64decode(result)
        assert len(decoded) > 0

    def test_output_changes_each_call(self):
        _, pub_hex = make_test_keypair()
        r1 = encrypt_instagram_password("123", pub_hex, "password")
        r2 = encrypt_instagram_password("123", pub_hex, "password")
        assert r1 != r2, "Each call must use a fresh AES key"

    def test_first_byte_is_version_1(self):
        _, pub_hex = make_test_keypair()
        result  = encrypt_instagram_password("1", pub_hex, "hello")
        decoded = base64.b64decode(result)
        assert decoded[0] == 1

    def test_second_byte_is_key_id(self):
        _, pub_hex = make_test_keypair()
        result  = encrypt_instagram_password("42", pub_hex, "hello")
        decoded = base64.b64decode(result)
        assert decoded[1] == 42

    def test_decryptable_password(self):
        """Round-trip: decrypt with the matching private key and verify the password."""
        password = "super_secret_password_123!"
        priv_key, pub_hex = make_test_keypair()

        result   = encrypt_instagram_password("1", pub_hex, password)
        raw      = base64.b64decode(result)

        encrypted_key_len = struct.unpack_from("<h", raw, 2)[0]
        offset            = 4
        encrypted_key     = raw[offset: offset + encrypted_key_len]
        offset           += encrypted_key_len
        cipher_tag        = raw[offset: offset + 16]
        offset           += 16
        encrypted_pass    = raw[offset:]

        box           = SealedBox(priv_key)
        aes_key       = box.decrypt(encrypted_key)

        aes = AES.new(aes_key, AES.MODE_GCM, nonce=bytes(12), mac_len=16)
        import time
        aes.update(str(int(time.time())).encode("utf-8"))
        decrypted = aes.decrypt(encrypted_pass)

        assert decrypted == password.encode("utf-8")

    def test_invalid_pub_key_raises(self):
        with pytest.raises(Exception):
            encrypt_instagram_password("1", "not_a_valid_hex_key", "pw")

    def test_empty_password_raises_or_encrypts(self):
        _, pub_hex = make_test_keypair()
        try:
            result = encrypt_instagram_password("1", pub_hex, "")
            assert isinstance(result, str)
        except Exception:
            pass


class TestFastAPIEndpoints:
    """Integration tests against the FastAPI app."""

    @pytest.fixture(autouse=True)
    def client(self):
        from fastapi.testclient import TestClient
        from app.main import app
        self.client = TestClient(app)

    def test_health_returns_ok(self):
        resp = self.client.get("/health")
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"

    def test_index(self):
        resp = self.client.get("/")
        assert resp.status_code == 200
        assert "rinstagram" in resp.json()["project"]

    def test_encrypt_endpoint(self):
        _, pub_hex = make_test_keypair()
        resp = self.client.post("/encrypt", json={"key_id": "1", "pub_key": pub_hex, "password": "test_pw"})
        assert resp.status_code == 200
        assert "encrypted" in resp.json()
        assert len(resp.json()["encrypted"]) > 10

    def test_encrypt_missing_field(self):
        resp = self.client.post("/encrypt", json={"key_id": "1"})
        assert resp.status_code == 422

    def test_encrypt_empty_password(self):
        _, pub_hex = make_test_keypair()
        resp = self.client.post("/encrypt", json={"key_id": "1", "pub_key": pub_hex, "password": ""})
        assert resp.status_code == 422
