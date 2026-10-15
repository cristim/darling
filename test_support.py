"""Pinned canonical source for host tests in public and standalone layouts."""

import hashlib
import os
from pathlib import Path

from build_guest import GUEST_SESSION_SHA256, PR1170_SHA, command, committed_inputs


def canonical_source() -> tuple[Path, bytes]:
    selected = os.environ.get("MST_TEST_CANONICAL_REPO")
    if selected is None:
        repo = Path(command(["git", "-C", str(Path(__file__).resolve().parent), "rev-parse", "--show-toplevel"]).decode().rstrip("\n"))
    else:
        repo = Path(selected)
        if not repo.is_absolute():
            raise ValueError("MST_TEST_CANONICAL_REPO must be an absolute repository path")
    try:
        data = committed_inputs(repo, PR1170_SHA, ("guest_session.py",), "tests/mst/")["guest_session.py"]
        blob = command(["git", "-C", str(repo), "rev-parse", f"{PR1170_SHA}:tests/mst/guest_session.py"]).decode().strip()
    except RuntimeError as error:
        raise RuntimeError("canonical host-test repository must contain the fixed reviewed commit; standalone tests may select its location with MST_TEST_CANONICAL_REPO") from error
    if hashlib.sha256(data).hexdigest() != GUEST_SESSION_SHA256 or blob != "a8b15f2cfe4cbc7598be940066ed5ef6ca8d2abb":
        raise ValueError("canonical host-test helper differs from the fixed reviewed digest/blob")
    return repo, data
