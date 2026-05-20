"""
Instagram v10 password encryption.

Pure function — no web-framework dependency, fully unit-testable.
"""

import base64
import binascii
import struct
import time

from Cryptodome import Random
from Cryptodome.Cipher import AES
from nacl.public import PublicKey, SealedBox


def encrypt_instagram_password(key_id: str, pub_key: str, password: str) -> str:
    """
    Encrypt a plaintext password using Instagram's v10 envelope scheme.

    Combines AES-256-GCM (random key per request) with NaCl SealedBox to
    encrypt the AES key against Instagram's RSA public key.

    Args:
        key_id:   Instagram key ID (decimal string) from the shared_data endpoint.
        pub_key:  Instagram public key (hex-encoded) from the shared_data endpoint.
        password: Plaintext Instagram password.

    Returns:
        Base64-encoded encrypted payload (without the ``#PWD_INSTAGRAM_BROWSER:10:`` prefix).
    """
    key          = Random.get_random_bytes(32)
    iv           = bytes([0] * 12)
    current_time = int(time.time())

    aes = AES.new(key, AES.MODE_GCM, nonce=iv, mac_len=16)
    aes.update(str(current_time).encode("utf-8"))
    encrypted_password, cipher_tag = aes.encrypt_and_digest(password.encode("utf-8"))

    pub_key_bytes = binascii.unhexlify(pub_key)
    seal_box      = SealedBox(PublicKey(pub_key_bytes))
    encrypted_key = seal_box.encrypt(key)

    payload = bytes(
        [
            1,
            int(key_id),
            *list(struct.pack("<h", len(encrypted_key))),
            *list(encrypted_key),
            *list(cipher_tag),
            *list(encrypted_password),
        ]
    )
    return base64.b64encode(payload).decode("utf-8")
