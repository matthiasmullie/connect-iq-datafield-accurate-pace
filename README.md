# Accurate Pace - a Garmin Connect IQ data field

**[Donate/Support: ![Support](https://www.mullie.eu/public/donate.png)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=K6NFGADC4SECN)**

Getting accurate pace from a GPS device is quite challenging.

Most GPS receivers are only accurate up to a few meters.
Even whensatellites line up perfectly, it's a near miracle that we're
able to get any usable pace at all.

With measurement intervals of only seconds, even the tiniest inaccuracy
heavily skews the data. When GPS coordinates are taken mere meters apart,
even an armswing is significant - and that's not even counting the
numerous challenges to even get that perfect GPS lock.

Since it's impossible to get accurate enough GPS coordinates, pace is
usually smoothened by increasing the window: the longer the distance
between the coordinates, the less that armswing or GPS inaccuracy will
matter, and the rolling average will remain pretty smooth.

The obvious downside there is responsiveness: a sudden slowdown or
increase in pace will barely show up, and it'll continue to influence
the pace for a little while longer.

I'd say Garmin has a pretty solid pace algorithm already, but here's
another approach.

The idea behind this algorithm is to use the past pace as a strong
indicator, which will be used to project the next coordinate.
It might be a few centimeters or even meters removed from the actual
position, but GPS likely isn't any more accurate (though it is less
consistent.) The GPS coordinates and data from other sensors (compass,
accelerometer, foot pod, ...) will be used to correct the projected
locations and keep it from going off track, though.

Most other smooth pace algorithms start with GPS or sensor data and
smoothen it (losing responsiveness to changes in pace) - this algorithm
starts from a smooth pace (based on recent pace) and uses the GPS data
to correct. The theory here is that this algorithm should be more
responsive to changes in pace, while also being more resilient to
momentarily poor GPS coverage.


## License

Accurate Pace is [MIT](http://opensource.org/licenses/MIT) licensed.
