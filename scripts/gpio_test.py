#!/usr/bin/env python3

from gpiozero import OutputDevice
from time import sleep

relay = OutputDevice(27)

print("GPIO27 ON")
relay.on()
sleep(5)

print("GPIO27 OFF")
relay.off()

print("終了")
