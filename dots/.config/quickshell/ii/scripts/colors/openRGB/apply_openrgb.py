#!/usr/bin/env python3
import sys
import os
from time import sleep, monotonic
import argparse
from subprocess import Popen
import json

try:
    from openrgb import OpenRGBClient
    from openrgb.utils import RGBColor
    from scipy.interpolate import interp1d
except ImportError as e:
    # Exit gracefully if optional openrgb / scipy python packages are not installed yet
    sys.exit(0)

try:
    import psutil
except ImportError:
    psutil = None

parser = argparse.ArgumentParser(description="Apply color on OpenRGB devices with a smooth transition")
parser.add_argument(
    "--duration",
    "-d",
    type=float,
    default=0.5,
    help="Duration of color swap animation",
)
parser.add_argument(
    "--interpolation-steps",
    "-i",
    type=int,
    default=100,
    help="Number of steps to swap the colors (lower=choppier, higher=smoother)",
)
parser.add_argument(
    "--color",
    "-c",
    type=str,
    help="HEX color to transition to",
)
args = parser.parse_args()

def hexToRGB(hexColor) -> list[int]:
    hexColor = hexColor.removeprefix("#")
    hexColor = [hexColor[i : i + 2] for i in range(0, 6, 2)]  # Split hex values
    intColor = [int(hexValue, 16) for hexValue in hexColor]  # Convert to int
    return intColor

def is_openrgb_running() -> bool:
    if psutil is not None:
        try:
            return any(p.name() == "openrgb" for p in psutil.process_iter())
        except Exception:
            pass
    return False

# At boot the OpenRGB server accepts connections before its hardware scan is
# finished (RAM/SMBus first, USB devices later). Wait until every configured
# device is listed, up to DEVICE_WAIT_TIMEOUT seconds, then apply what we have.
DEVICE_WAIT_TIMEOUT = 30.0
DEVICE_WAIT_DELAY = 1.0

def get_client(name: str = "quickshell", expected: int = 0):
    deadline = monotonic() + DEVICE_WAIT_TIMEOUT
    best = None
    while True:
        try:
            client = OpenRGBClient(name=name)
            if len(client.devices) >= expected:
                if best is not None and best is not client:
                    try:
                        best.disconnect()
                    except Exception:
                        pass
                return client
            # Device list incomplete: scan not finished. Keep the fullest
            # client as fallback and retry with a fresh connection.
            if best is None or len(client.devices) > len(best.devices):
                if best is not None:
                    try:
                        best.disconnect()
                    except Exception:
                        pass
                best = client
            else:
                try:
                    client.disconnect()
                except Exception:
                    pass
        except Exception:
            if not is_openrgb_running():
                try:
                    Popen(["openrgb", "--server", "--startminimized"])
                except Exception:
                    pass
        if monotonic() >= deadline:
            return best
        sleep(DEVICE_WAIT_DELAY)

TRANSITION_DURATION = args.duration
INTERPOLATION_STEPS = args.interpolation_steps

xdg_state_home = os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state"))
xdg_config_home = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
state_dir = os.path.join(xdg_state_home, "quickshell")

config_path = os.path.join(xdg_config_home, "illogical-impulse", "config.json")
if not os.path.exists(config_path):
    config_path = os.path.join(xdg_config_home, "immaterial-impulse", "config.json")

if not os.path.exists(config_path):
    sys.exit(0)

try:
    with open(config_path, "r") as f:
        config = json.load(f)
except Exception:
    sys.exit(0)

openrgb_opts = config.get("appearance", {}).get("openrgb", {})
if not openrgb_opts.get("enable", False):
    sys.exit(0)

devices = openrgb_opts.get("devices", [])
if not any(d.get("enabled", False) for d in devices):
    sys.exit(0)

expected_devices = (
    max(
        (d["id"] for d in devices if d.get("enabled", False) and d.get("id") is not None),
        default=-1,
    )
    + 1
)

client = get_client(expected=expected_devices)
if client is None:
    sys.exit(0)

color_file = os.path.join(state_dir, "user", "generated", "color.txt")
new_color = [255, 255, 255]
if os.path.exists(color_file):
    try:
        with open(color_file, "r") as f:
            new_color = hexToRGB(f.read().strip())
    except Exception:
        pass

if args.color is not None:
    new_color = hexToRGB(args.color)

try:
    for dev in devices:
        if dev.get("enabled", False) and dev.get("id") is not None:
            dev_id = dev["id"]
            if dev_id >= len(client.devices):
                continue
            if client.devices[dev_id].active_mode == 1:  # 1 = Off
                old_color = [0, 0, 0]
            else:
                old_color = [
                    client.devices[dev_id].leds[0].colors[0].red,
                    client.devices[dev_id].leds[0].colors[0].green,
                    client.devices[dev_id].leds[0].colors[0].blue,
                ]
            dev["interpolation"] = interp1d([0, 1], [old_color, new_color], axis=0)

    for i in range(INTERPOLATION_STEPS):
        t = i / (INTERPOLATION_STEPS - 1) if INTERPOLATION_STEPS > 1 else 1.0

        for dev in devices:
            if dev.get("enabled", False) and dev.get("id") is not None and "interpolation" in dev:
                dev_id = dev["id"]
                if dev_id >= len(client.devices):
                    continue
                interp_color = [int(val) for val in dev["interpolation"](t)]
                client.devices[dev_id].set_color(RGBColor(*interp_color), True)
                if client.devices[dev_id].active_mode != 0:
                    client.devices[dev_id].set_mode(mode=0)

        sleep(TRANSITION_DURATION / INTERPOLATION_STEPS)
except Exception:
    pass