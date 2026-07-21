#!/bin/bash
#
# ==================================================
# SVXLink JP Edition
# GPIO Controller
# Developed by JQ1YOF
# ==================================================

CONFIG="$HOME/SVXLinkJP/config/config.ini"

if [ -f "$CONFIG" ]; then
    source "$CONFIG"
else
    POWER_GPIO=27
fi

GPIO=${POWER_GPIO:-27}

case "$1" in
    on)
        pinctrl set $GPIO op dh
        echo "===================================="
        echo " Radio Power : ON"
        echo " GPIO        : $GPIO"
        echo "===================================="
        ;;
    off)
        pinctrl set $GPIO op dl
        echo "===================================="
        echo " Radio Power : OFF"
        echo " GPIO        : $GPIO"
        echo "===================================="
        ;;
    status)
        echo
        echo "GPIO Status"
        pinctrl get $GPIO
        ;;
    test)
        echo
        echo "GPIO TEST START"
        pinctrl set $GPIO op dh
        sleep 2
        pinctrl set $GPIO op dl
        echo "TEST COMPLETE"
        ;;
    *)
        echo
        echo "SVXLink JP Edition"
        echo
        echo "Usage:"
        echo "  gpio.sh on"
        echo "  gpio.sh off"
        echo "  gpio.sh status"
        echo "  gpio.sh test"
        ;;
esac
