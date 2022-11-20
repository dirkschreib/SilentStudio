# SilentStudio
Set fan speed of Mac Studio

## How to use?
Inside terminal:
```
sudo ./SilentStudio.swift -h
usage: SilentStudio [--] [<temp> <rpm>]* [-d] [-h] [-i <sec>] [-s <sensor>*]

  options
  <temp> <rpm>     Pair(s) of temperature and rpm. "AUTO" for automatic setting. Default: [(key: 0.0, value: "0"), (key: 50.0, value: "0"), (key: 60.0, value: "AUTO")]
  -d               Debug mode. List every value read and written
  -h               This help text
  -i <sec>         Checks every <sec> seconds. Default: 30.0
  -s <sensor>*     List of sensors to read. Default: ["TT0D", "TT1D", "TT2D"]
          
 Program will run in an endless loop. Use ctrl-c to stop. Fans will be resetted to AUTO mode.
```
If you forget the sudo part, it will remind you:
```
dirk@Mac-Studio-von-Dirk SilentStudio % ./SilentStudio.swift 
2022-11-14 12:11:06 current: 58.44, last: 0.0, rpm: 1338.091,1315.7894
2022-11-14 12:11:06 change: Set fans to 0 rpm
2022-11-14 12:11:06 set  F0Md: 1
2022-11-14 12:11:06 catched error: -536870207. started with sudo?
```
Stop the script with ctrl-c. It will reset both fans to "AUTO" mode.

## How does it work?
The script uses a small dictionary `targetrpm`to set the rpm values of both fans inside the Mac Studio whenever a temperature "border" has been crossed.
The default setting switches the fan off for temperatures below 50°C and switches to "AUTO" mode whenever the temperature crosses 60°C. "AUTO" is the builtin standard behaviour. It always seems to be in the range from 1320-1330 rpm. The temperature is checked every 30 seconds.

| Temperature in °C| rpm |
| ----------- | --- |
| 1.0 | 0 |
| 50.0 | 0 |
| 60.0 | AUTO |

## How to change default behaviour?
Currently you have to change the script lines 15 to 22. 

The `checkinterval` defines the duration between checks in seconds. Needs to be one seconds or greater.
With the dictionary `targetrpm` you can define as many (temperature, rpm) value pairs as you want. Values below ~550 rpm will not work.

The temperature sensor I check in my example is "TT0D" (see line 212). This is the first (i.e 0) thunderbolt port. On an idle Mac Studio this is the sensor with the most volatility. I will probable expand this to check the CPU and GPU temperature as well in the future.

# Disclaimer
Use on your own risk. Don't use with CPU/GPU intensive tasks.
