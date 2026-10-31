"""Create an external Linux Ed25519 key and register only its public key."""

import argparse
import os
from pathlib import Path
import tempfile

from common import CONFIG, ROOT, load_json, public_key, run, write_json


def initialize(destination: Path, key_id: str, configuration: Path) -> None:
    destination = destination.expanduser().resolve()
    if destination.is_relative_to(ROOT) or destination.exists():
        raise ValueError("Choose a new private-key path outside the repository; existing keys are never replaced.")
    if not key_id or any(character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_" for character in key_id):
        raise ValueError("Key IDs must contain letters, numbers, hyphens or underscores.")
    config = load_json(configuration)
    if key_id in config["trusted_keys"]:
        raise ValueError("That signing identity is already configured. Restore its existing private key.")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".phonolite-key-", dir=destination.parent) as temporary:
        generated = Path(temporary) / "key.pem"
        run(["openssl", "genpkey", "-algorithm", "ED25519", "-out", str(generated)])
        descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as output:
            output.write(generated.read_bytes())
        config["trusted_keys"][key_id] = public_key(destination)
        write_json(configuration, config)
    print(f"Public key {key_id} registered in {configuration}. Back up the external private key securely.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--private-key", type=Path, required=True)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--config", type=Path, default=CONFIG)
    arguments = parser.parse_args()
    initialize(arguments.private_key, arguments.key_id, arguments.config)


if __name__ == "__main__":
    main()
