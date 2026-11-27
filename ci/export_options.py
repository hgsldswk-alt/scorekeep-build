"""Render signing options for the app without reading credentials."""
import os
from pathlib import Path
import plistlib
import sys

data = plistlib.loads(Path(__file__).with_name("ExportOptions.plist").read_bytes())
data["teamID"] = os.environ["TEAM_ID"]
app_id = os.environ.get("APP_ID", "com.hgsldswk.scorekeep")
data["provisioningProfiles"] = {app_id: os.environ.get("APP_PROFILE", "ScoreKeeper AppStore")}
sys.stdout.buffer.write(plistlib.dumps(data))
