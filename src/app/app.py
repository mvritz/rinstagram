import base64
import binascii
import struct
import time

import flask
from Cryptodome import Random
from Cryptodome.Cipher import AES
from flask import request
from nacl.public import PublicKey, SealedBox

app = flask.Flask(__name__)


@app.route("/encrypt", methods=["POST"])
def encrypt() -> str:
    data = request.get_json()

    key_id: str = data["key_id"]
    pub_key: str = data["pub_key"]
    password: str = data["password"]

    key = Random.get_random_bytes(32)
    iv = bytes([0] * 12)
    current_time = int(time.time())

    aes = AES.new(key, AES.MODE_GCM, nonce=iv, mac_len=16)
    aes.update(str(current_time).encode("utf-8"))
    encrypted_password, cipher_tag = aes.encrypt_and_digest(password.encode("utf-8"))

    pub_key_bytes = binascii.unhexlify(pub_key)
    seal_box = SealedBox(PublicKey(pub_key_bytes))
    encrypted_key = seal_box.encrypt(key)

    encrypted = bytes(
        [
            1,
            int(key_id),
            *list(struct.pack("<h", len(encrypted_key))),
            *list(encrypted_key),
            *list(cipher_tag),
            *list(encrypted_password),
        ]
    )
    encrypted = base64.b64encode(encrypted).decode("utf-8")

    return encrypted


if __name__ == "__main__":
    app.run()