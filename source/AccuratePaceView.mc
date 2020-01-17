using Toybox.WatchUi;
using Toybox.Position;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.Time;

class AccuratePaceView extends WatchUi.SimpleDataField {

	// @see https://en.wikipedia.org/wiki/Earth_ellipsoid#Historical_Earth_ellipsoids
	protected var earthMeanRadius = 6378137.0;
	protected var units;

	// will hold the most recent GPS positions & their timestamps
	protected var recentLocations = [];
	protected var recentProjections = [];
	protected var recentMoments = [];
	protected var relevancyWindow = 20; // in seconds
	protected var lastLocation = new Position.Location({:latitude => 0, :longitude => 0, :format => :radians});
	protected var lastMoment = new Time.Moment(0);

	// minimum required amount of recent coordinates (within window) to start projecting from
	protected var reliabilityMinimum = 3;

	function initialize() {
		SimpleDataField.initialize();

		var language = System.getDeviceSettings().systemLanguage;
		var labels = {
			System.LANGUAGE_ARA => "سرعة",
			System.LANGUAGE_BUL => "темпо",
			System.LANGUAGE_CES => "TEMPO",
			System.LANGUAGE_CHS => "步伐",
			System.LANGUAGE_CHT => "步伐",
			System.LANGUAGE_DAN => "PACE",
			System.LANGUAGE_DEU => "TEMPO",
			System.LANGUAGE_DUT => "TEMPO",
			System.LANGUAGE_ENG => "PACE",
			System.LANGUAGE_EST => "TEMPO",
			System.LANGUAGE_FIN => "VAUHTI",
			System.LANGUAGE_FRE => "RHYTME",
			System.LANGUAGE_GRE => "Βήμα",
			System.LANGUAGE_HEB => "קצב",
			System.LANGUAGE_HRV => "TEMPO",
			System.LANGUAGE_HUN => "SEBESSéG",
			System.LANGUAGE_IND => "KECEPATAN",
			System.LANGUAGE_ITA => "RITMO",
			System.LANGUAGE_JPN => "ペース",
			System.LANGUAGE_KOR => "속도",
			System.LANGUAGE_LAV => "TEMPS",
			System.LANGUAGE_LIT => "TEMPAS",
			System.LANGUAGE_NOB => "PACE",
			System.LANGUAGE_POL => "TEMPO",
			System.LANGUAGE_POR => "RITMO",
			System.LANGUAGE_RON => "RITM",
			System.LANGUAGE_RUS => "аллюр",
			System.LANGUAGE_SLO => "TEMPO",
			System.LANGUAGE_SLV => "PACE",
			System.LANGUAGE_SPA => "PASE",
			System.LANGUAGE_SWE => "TAKT",
			System.LANGUAGE_THA => "ก้าว",
			System.LANGUAGE_TUR => "HıZ",
			System.LANGUAGE_UKR => "ПАРЄ",
			System.LANGUAGE_VIE => "TỐC ĐỘ",
			System.LANGUAGE_ZSM => "പേസ്",
		};

		self.label = labels[language];
		self.units = System.getDeviceSettings().paceUnits;
	}

	function compute(info) {
		self.updateLocation();

		var pace = 0;

		var relevantSecondsAgo = 5;
		var recentPaces = [];
		var recentDurations = [];
		for (var i = self.recentMoments.size() - 1; i > 0; i--) {
			if (Time.now().compare(self.recentMoments[i]) > relevantSecondsAgo) {
				break;
			}

			var elapsedTime = self.recentMoments[i].compare(self.recentMoments[i - 1]);
			var elapsedDistance = self.calculateDistance(self.recentProjections[i - 1], self.recentProjections[i]);
			if (elapsedTime > 0) {
				recentDurations.add(elapsedTime);
				var pace = elapsedDistance > 0 ? elapsedTime / elapsedDistance : 0;
				recentPaces.add(pace);
			}
		}

		if (recentPaces.size() > 1) {
			// instead of using the average pace over the last few measurements, we're going
			// to average the 40, 50 and 60 weighted percentile:
			// - an average on the whole dataset would make the results slow: it would take
			//   awhile for a slowdown to show up (weighed up by older fast paces), and the
			//   momentary slowness would drag us down for quite awhile longer
			// - on the other hand, using the mean (or 50% quantile) saves us from those
			//   outliers, but will make for a very jumpy pace since it's only 1 value...
			var weight = new WeightedQuantile(recentPaces, recentDurations);
			var smoothenedPace = (weight.calculate(0.4) + weight.calculate(0.5) + weight.calculate(0.6)) / 3;
			var currentPace = recentPaces[recentPaces.size() - 1];

			// in order to compare the 2, it'll be more useful to convert them back to
			// a "distance" unit rather than pace (time over distance)
			var smoothenedDistance = smoothenedPace > 0 ? 1 / smoothenedPace : 0;
			var currentDistance = currentPace > 0 ? 1 / currentPace : 0;
			var diff = currentDistance > smoothenedDistance ? currentDistance - smoothenedDistance : smoothenedDistance - currentDistance;

			if (
				diff > smoothenedDistance / 6 &&
				diff < smoothenedDistance &&
				info has :currentSpeed && info.currentSpeed != null && info.currentSpeed > 0 &&
				diff < 1 / info.currentSpeed / 3
			) {
				// there's a significant enough change in pace (though still realistic - a
				// change *too big* is likely a GPS correction) and it's backed up by sensors
				pace = currentPace;
			} else {
				// change in pace is either unrealistic, or insignificant enough that we'll
				// want to keep showing a smooth-ish pace
				pace = smoothenedPace;
			}
		} else if (info has :currentSpeed && info.currentSpeed != null && info.currentSpeed > 0) {
			// try to fall back to speed provided by system (possibly from other sources, like
			// foot pods or accelerometer) if we have no reliable own pace
			pace = 1 / info.currentSpeed;
		}

		if (pace == 0 || pace > 2.5) {
			return "--:--";
		}

		var minutesPerKm = pace / (60.0 / 1000.0);
		return self.formatTime(self.convertUnits(minutesPerKm));
	}

	function updateLocation() {
		// it's not possible to subscribe to position updates from a datafield, so we're going
		// to have to make do with the data we'll get here; this means we could miss out on a
		// few coordinates if there have been GPS recordings in between 2 compute() calls, but
		// we'll manage... Ideally, these few lines below would just be this:
		// Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPositionUpdate));
		// (I'm using Position.getInfo() instead of info.currentLocation because we need the exact
		// timestamp - position.when - of the GPS fix)
		var position = Position.getInfo();

		if (
			position.accuracy != Position.QUALITY_NOT_AVAILABLE &&
			position.accuracy != Position.QUALITY_LAST_KNOWN &&
			position.when.compare(self.lastMoment) > 0 &&
			!position.position.toGeoString(Position.GEO_MGRS).equals(self.lastLocation.toGeoString(Position.GEO_MGRS)) &&
			(position.position.toRadians()[0].toFloat() != 0.0 || position.position.toRadians()[1].toFloat() != 0.0) &&
			(position.position.toRadians()[0].toFloat() != Math.PI || position.position.toRadians()[1].toFloat() != Math.PI)
		) {
			self.onPositionUpdate(position);
			self.lastMoment = position.when;
			self.lastLocation = position.position;
		}
	}

	function onPositionUpdate(info) {
		// omit old values - they're no longer relevant
		var now = Time.now();
		var sliceIndex = 0;
		for (var i = 0; i < self.recentMoments.size(); i++) {
			if (now.compare(self.recentMoments[i]) <= self.relevancyWindow) {
				break;
			}
			sliceIndex = i;
		}
		self.recentMoments = self.recentMoments.slice(sliceIndex, null);
		self.recentLocations = self.recentLocations.slice(sliceIndex, null);
		self.recentProjections = self.recentProjections.slice(sliceIndex, null);

		// project the next location based on the new GPS coordinates and the past pace/angle
		var projectedLocation = self.getProjectedLocation(info);

		// store new position & timestamp
		self.recentMoments.add(info.when);
		self.recentLocations.add(info.position);
		self.recentProjections.add(projectedLocation);

		// if distance from GPS becomes too big, then go back and adjust recent projections
		var distanceFromGps = self.calculateDistance(info.position, projectedLocation);
		var accuracyInMeters = self.getLocationAccuracyInMeters(info.accuracy);
		if (distanceFromGps > 0 && distanceFromGps > accuracyInMeters / 2) {
			var fixedPosition = self.getIntermediateCoordinate(
				projectedLocation,
				info.position,
				accuracyInMeters / 2 / distanceFromGps
			);

			// after having "fixed" our most recent projection, which was way off,
			// we'll want to adjust most recent projections as well: we didn't suddenly
			// warp to the new location, but we got there gradually, and apparently
			// we've been projecting that incorrectly
			// we'll simply adjust the existing locations relative the new fixed location
			self.recentProjections[self.recentProjections.size() - 1] = fixedPosition;
			for (var i = self.recentProjections.size() - 2; i > 0; i--) {
				var distanceFromProjection = self.calculateDistance(self.recentProjections[i], projectedLocation);
				var distanceFromFix = self.calculateDistance(self.recentProjections[i], self.recentProjections[self.recentProjections.size() - 1]);
				self.recentProjections[i] = self.getIntermediateCoordinate(
					self.recentProjections[i - 1],
					self.recentProjections[i],
					distanceFromProjection / distanceFromFix
				);
			}
		}
	}

	function getProjectedLocation(info) {
		// so, why is GPS-based pace often erratic?
		// with GPS locations taken at small enough intervals, even the tiniest deviation
		// matters - when taken only a few meters apart, even an armswing is significant
		// paces can be smoothened by averaging them over a larger period of time, but then
		// they'll lag behind, drastically, which kind of defeats the idea behind current pace
		// let's try something different for a change: let's "predict" where our next
		// coordinate will be based on our existing pace & angle, and use the GPS
		// location & accuracy to course correct (e.g. actual change in pace or direction)

		// let's make sure we have sufficient source data before we start deriving
		// more data from it - let's trust GPS until we have a decent enough basis
		if (self.recentProjections.size() < self.reliabilityMinimum || self.recentProjections.size() <= 0) {
			return info.position;
		}

		// projectedLocation is where we predict we'll be based on GPS or data from other
		// sensors (depending on GPS accuracy), smoothened by recent pace & angle
		var lastLocation = self.recentProjections[self.recentProjections.size() - 1];
		return lastLocation.getProjectedLocation(
			self.getProjectedAngle(info),
			self.getProjectedDistance(info)
		);
	}

	function getProjectedDistance(info) {
		var lastLocation = self.recentProjections[self.recentProjections.size() - 1];
		var lastMoment = self.recentMoments[self.recentMoments.size() - 1];
		var duration = info.when.compare(lastMoment);

		// get distance from new GPS location
		var gpsDistance = self.calculateDistance(lastLocation, info.position);

		// derive angle & distance based on recent data
		var recentDistance = 0;
		try {
			var recentPace = self.getRecentPace();
			recentDistance = recentPace > 0 ? duration / recentPace : 0;
		} catch (e instanceof Lang.Exception) {
			return gpsDistance;
		}

		// let's compare recent data against current sensor data (possibly from other
		// sources, like foot pod or accelerometer) to validate it: the closer they match,
		// the better the odds it's accurate
		var sensorsDistance = duration * info.speed;
		var distanceDiffFromSensors = recentDistance > sensorsDistance ? recentDistance - sensorsDistance : sensorsDistance - recentDistance;

		// GPS can be very erratic, but the GPS location and the accuracy of the GPS does
		// give us an indication of where we should expect to be - it's more of an area
		// than it is a specific - detailed - coordinate, though...
		var accuracyInMeters = self.getLocationAccuracyInMeters(info.accuracy);
		var distanceDiffFromGps = recentDistance > gpsDistance ? recentDistance - gpsDistance : gpsDistance - recentDistance;

		// if our data roughly matches the sensors (= not indicating a massive slowdown
		// or pace increase), and we're close enough to the GPS, then just keep using the
		// recent pace without correction
		if (distanceDiffFromSensors < recentDistance / 6 && distanceDiffFromGps < accuracyInMeters / 2) {
			if (recentDistance == sensorsDistance) {
				return recentDistance;
			}
			// use recent data as basis, with a correction toward sensor data
			var sensorsCorrection = distanceDiffFromSensors / sensorsDistance * 6;
			return recentDistance * (1 - sensorsCorrection) + sensorsDistance * sensorsCorrection;
		}

		// if we're not too far from GPS, but not quite dead on, then the sensors data
		// are quite a good indicator to balance out the recent pace
		if (distanceDiffFromGps < accuracyInMeters) {
			if (accuracyInMeters == 0 || sensorsDistance == gpsDistance) {
				return gpsDistance;
			}
			// use sensor data as basis, with a minor correction toward GPS data
			var distanceDiff = sensorsDistance > gpsDistance ? sensorsDistance - gpsDistance : gpsDistance - sensorsDistance;
			var gpsCorrection = (distanceDiff <= sensorsDistance ? distanceDiff / sensorsDistance : distanceDiff / gpsDistance) / accuracyInMeters / 2;
			return sensorsDistance * (1 - gpsCorrection) + gpsDistance * gpsCorrection;
		}

		// there's no salvaging this, all of the data conflicts
		// let's go with recent pace, and then trust that the additional checks
		// later on will leverage GPS in a good enough way to rewrite the history
		// of recent locations
		return recentDistance;
	}

	function getProjectedAngle(info) {
		var lastLocation = self.recentProjections[self.recentProjections.size() - 1];

		// get angle & distance from new GPS locations
		var gpsAngle = self.calculateBearing(lastLocation, info.position);
		var gpsDistance = self.calculateDistance(lastLocation, info.position);

		var recentAngle = 0;
		try {
			recentAngle = self.getRecentAngle();
		} catch (e instanceof Lang.Exception) {
			return gpsAngle;
		}

		// the further away the next GPS coordinate is, and the smaller the accuracy
		// radius, the more precise the angle provided by GPS is (if it's 100m ahead
		// of us, with accuracy up to a few meters, the angle between the outer edges
		// of the accuracy zone is pretty damn small)
		var accuracyInMeters = self.getLocationAccuracyInMeters(info.accuracy);
		var gpsAccuracyAngleDegrees = gpsDistance > 0 && gpsDistance > accuracyInMeters / 2 ? Math.acos((2 * Math.pow(gpsDistance, 2) - Math.pow(accuracyInMeters, 2)) / (2 * Math.pow(gpsDistance, 2))) / (Math.PI / 180.0) : 360;
		var gpsAccuracy = 1 - (gpsAccuracyAngleDegrees / 2 / 180);
		gpsAccuracy = gpsAccuracy > 0 ? gpsAccuracy : 0.001;

		// if the angle we've gotten from GPS has sufficient precision and the angle
		// we've gotten based on recent data is not within the GPS accuracy bounds,
		// it can't be trusted
		var recentAngleDiffFromGps = self.calculateAngle(gpsAngle, recentAngle) / (Math.PI / 180.0);
		if (gpsAccuracyAngleDegrees < 360 && recentAngleDiffFromGps.abs() > gpsAccuracyAngleDegrees / 2) {
			return gpsAngle;
		}

		// figure out how accurate our recent angle is relative to sensor data (e.g. compass)
		// if it's within a 45 degrees angle (22.5 on either side, 1/8 of a full circle)
		// then we're golden
		var sensorsAngle = info.heading;
		var angleDiffDegrees = self.calculateAngle(sensorsAngle, recentAngle) / (Math.PI / 180.0);
		var recentAccuracy = angleDiffDegrees.abs() / 22.5;
		recentAccuracy = recentAccuracy < 1 ? Math.sqrt(1 - recentAccuracy) : 0.001;

		// let's factor in the differences in distance between the new GPS coordinate and
		// our recent pace: if they're far apart, we might want to boost the GPS angle over
		// the recent angle
		// the GPS angle might be way off, but we also may have started turning, and then
		// we'll have to make up even more after having gone in a different direction
		var duration = info.when.compare(lastMoment);
		var recentDistance = 0;
		try {
			var recentPace = self.getRecentPace();
			recentDistance = recentPace > 0 ? duration / recentPace : 0;
		} catch (e instanceof Lang.Exception) {
			// meh...
		}
		var distanceDiffFromGps = recentDistance > gpsDistance ? recentDistance - gpsDistance : gpsDistance - recentDistance;
		if (distanceDiffFromGps > recentDistance / 2 || distanceDiffFromGps > gpsDistance / 2) {
			var distanceMultiplier = distanceDiffFromGps < gpsDistance ? distanceDiffFromGps / gpsDistance : distanceDiffFromGps / recentDistance;
			gpsAccuracy *= distanceMultiplier;
			recentAccuracy *= 1.0 - distanceMultiplier;
		}

		// calculate an angle from combined GPS data & recent direction, based on how
		// accurate we've estimated them both to be (and both could have really poor
		// accuracy, in which case we'll end up somewhere in the middle)
		return Math.atan2(
			Math.sin(gpsAngle) * gpsAccuracy + Math.sin(recentAngle) * recentAccuracy,
			Math.cos(gpsAngle) * gpsAccuracy + Math.cos(recentAngle) * recentAccuracy
		);
	}

	function getRecentPace() {
		if (self.recentProjections.size() < 2) {
			throw new Lang.Exception(/* Insufficient data */);
		}

		// GPS is quite imprecise - even with maximum accuracy, we'll have locations
		// a few meters apart for some time, only for it to then jump 10+ meters
		// all of a sudden, over the same time interval, at the same pace...
		// so our recent pace will be a rolling average over multiple GPS locations,
		// to smoothen out those jumps
		var duration = self.recentMoments[self.recentMoments.size() - 1].compare(self.recentMoments[0]);
		var projectedDistance = 0;
		var gpsDistance = 0;
		for (var i = 0; i < self.recentProjections.size() - 1; i++) {
			projectedDistance += self.calculateDistance(self.recentProjections[i], self.recentProjections[i + 1]);
			gpsDistance += self.calculateDistance(self.recentLocations[i], self.recentLocations[i + 1]);
		}

		// the goal is for the projected distance to be (slightly) less than the GPS
		// distance, which may have some left/right jitter
		// if, however, that is not the case, it's likely because we've strayed from
		// the track (e.g. turned) and using the projected distance would give us an
		// exaggerated pace (more distance covered than is actually the case)
		var distance = gpsDistance < projectedDistance ? gpsDistance : projectedDistance;

		return distance > 0 ? duration / distance : 0;
	}

	function getRecentAngle() {
		if (self.recentProjections.size() < 2) {
			throw new Lang.Exception(/* Insufficient data */);
		}

		// we'll iterate recent positions to determine the current bearing;
		// we'll take the oldest bearing first and keep refining until the most
		// recent bearing
		var recentBearing = self.calculateBearing(self.recentProjections[0], self.recentProjections[1]);
		for (var i = 1; i < self.recentProjections.size() - 1; i++) {
			var bearing = self.calculateBearing(self.recentProjections[i], self.recentProjections[i + 1]);
			var diffInDegrees = self.calculateAngle(recentBearing, bearing) / (Math.PI / 180.0);
			diffInDegrees = diffInDegrees > 0 ? diffInDegrees : -diffInDegrees;
			if (diffInDegrees > 11.25) {
				// if the angle is not within a 22.5 degrees (11.25 on either side) of the
				// most recent angle, we've probably turned and the older bearings become
				// irrelevant
				recentBearing = bearing;
			}

			// refine the current bearing using this bearing;
			// most recent bearings will be calculated last, so they'll have the most impact
			recentBearing = Math.atan2(
				Math.sin(recentBearing) + Math.sin(bearing),
				Math.cos(recentBearing) + Math.cos(bearing)
			);
		}

		return recentBearing;
	}

	function haversin(theta) {
		return (1 - Math.cos(theta)) / 2;
	}

	function calculateDistance(location1, location2) {
		var lat1 = location1.toRadians()[0];
		var lng1 = location1.toRadians()[1];
		var lat2 = location2.toRadians()[0];
		var lng2 = location2.toRadians()[1];

		if (lat1 == lat2 && lng1 == lng2) {
			return 0;
		}

		var h = self.haversin(lat2 - lat1) + Math.cos(lat1) * Math.cos(lat2) * self.haversin(lng2 - lng1);
		return 2 * self.earthMeanRadius * Math.asin(Math.sqrt(h));
	}

	function calculateBearing(location1, location2) {
		var lat1 = location1.toRadians()[0];
		var lng1 = location1.toRadians()[1];
		var lat2 = location2.toRadians()[0];
		var lng2 = location2.toRadians()[1];

		var x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(lng2 - lng1);
		var y = Math.cos(lat2) * Math.sin(lng2 - lng1);

		var bearing = Math.atan2(y, x);

		// normalize to negative values west & positive values east
		return bearing > Math.PI ? bearing - 2.0 * Math.PI : bearing;
	}

	function calculateAngle(bearing1, bearing2) {
		var bearing1y = Math.cos(bearing1);
		var bearing1x = Math.sin(bearing1);
		var bearing2y = Math.cos(bearing2);
		var bearing2x = Math.sin(bearing2);

		var sign = bearing1y * bearing2x >= bearing2y * bearing1x ? 1.0 : -1.0;
		return sign * Math.acos(bearing1x * bearing2x + bearing1y * bearing2y);
	}

	function getIntermediateCoordinate(location1, location2, fraction) {
		if (fraction == 0) {
			return location1;
		}

		if (fraction == 1) {
			return location2;
		}

		var angularDistance = self.calculateDistance(location1, location2) / self.earthMeanRadius;
		if (angularDistance == 0) {
			return location1;
		}

		var lat1 = location1.toRadians()[0];
		var lng1 = location1.toRadians()[1];
		var lat2 = location2.toRadians()[0];
		var lng2 = location2.toRadians()[1];

		var a = Math.sin((1 - fraction) * angularDistance) / Math.sin(angularDistance);
		var b = Math.sin(fraction * angularDistance) / Math.sin(angularDistance);
		var x = a * Math.cos(lat1) * Math.cos(lng1) + b * Math.cos(lat2) * Math.cos(lng2);
		var y = a * Math.cos(lat1) * Math.sin(lng1) + b * Math.cos(lat2) * Math.sin(lng2);
		var z = a * Math.sin(lat1) + b * Math.sin(lat2);
		var lat = Math.atan2(z, Math.sqrt(Math.pow(x, 2) + Math.pow(y, 2)));
		var lng = Math.atan2(y, x);

		return new Position.Location({:latitude => lat, :longitude => lng, :format => :radians});
	}

	function getDOP(accuracy) {
		// a guess at the dilution of precision based on Garmin's GPS quality constants
		// @see https://developer.garmin.com/downloads/connect-iq/monkey-c/doc/Toybox/Position.html
		// @see https://en.wikipedia.org/wiki/Dilution_of_precision_(navigation)
		var qualityToDOP = {
			Position.QUALITY_NOT_AVAILABLE => 9999999999999, // useless
			Position.QUALITY_LAST_KNOWN => 9999999999999, // useless
			Position.QUALITY_POOR => 14,
			Position.QUALITY_USABLE => 7,
			Position.QUALITY_GOOD => 3,
		};

		return qualityToDOP[accuracy];
	}

	function getLocationAccuracyInMeters(accuracy) {
		// by their own account, Garmin devices should be accurate up to 3m
		// @see https://support.garmin.com/en-US/?faq=P3DdzRfgik3fky125aHsFA
		var bestAccuracy = 3.0;

		// while not reliable, multiplying best accuracy with HDOP will provide
		// a rough guesstimate in meters
		// @see https://gis.stackexchange.com/questions/377/calculating-absolute-precision-confidence-number-from-dilution-of-precision-indi
		return self.getDOP(accuracy) * bestAccuracy;
	}

	function convertUnits(minutesPerKm) {
		if (self.units == System.UNIT_STATUTE) {
			return minutesPerKm / 0.621371192;
		}
		return minutesPerKm;
	}

	function formatTime(minutes) {
		var seconds = Math.round((minutes * 60).toLong() % 60 / 5) * 5;
		return Lang.format("$1$:$2$", [minutes.format("%d"), seconds.format("%02d")]);
	}

}