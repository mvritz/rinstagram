# Instagram Password Encryption API

## Introduction

This is a simple API that encrypts Instagram passwords for web login which is necessary for the login request to work.
The function is written in Python and yes, I have to admit that I did not manage to convert this function to an `R`
function. This is the reason why I decided to write a simple API that can be used to encrypt Instagram passwords.

## Documentation

The deployment of the API is hostet on **[railway](https://railway.app/)**. The API is available under the following
URL:

> **https://rinstagram-production.up.railway.app/**

### Endpoint Documentation for `/encrypt`

This endpoint is used to encrypt an Instagram password for web login and registration for version 10 of the Instagram
encryption algorithm.

#### Supported Operation Method(s): `POST`

#### Request Body:

| Field      | Type   | Required | Description                                                 |
|------------|--------|----------|-------------------------------------------------------------|
| `key_id`   | string | Yes      | Identifier for the public key used in encryption            |
| `pub_key`  | string | Yes      | Public key in hexadecimal format for encrypting the AES key |
| `password` | string | Yes      | Password to be encrypted                                    |

#### Example cURL Request:

```bash
curl -X POST 'https://rinstagram-production.up.railway.app/encrypt' \
-H 'Content-Type: application/json' \
-d '{
    "key_id": "12345",
    "pub_key": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6",
    "password": "test1234"
}'
```

## Deployment

You can also run the API locally by following the instructions below.

### Requirements

Please make sure that you have Python `3.8` or higher installed on your system. After that, you can install the required
packages by running the following command:

```bash
pip install -r requirements.txt
```

or if you are on a Unix-based system:

```bash
pip3 install -r requirements.txt
```

To deploy the API you can run the following command inside the `app/` directory:

```bash
gunicorn app:app
```

## Explanation

The `encrypt` function uses both symmetric and asymmetric encryption methods to secure a password. It first encrypts the
password using AES in GCM mode from the `Cryptodome.Cipher` package, generating a random 32-byte key and a static
initialization vector. After AES encryption, it uses a public key, assumed to be from the `nacl.public` package, to
encrypt the AES key itself in a sealed box format.