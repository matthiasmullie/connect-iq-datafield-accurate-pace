using Toybox.Lang;

class WeightedQuantile {

	protected var sortedData = [];
	protected var sortedBase = [];
	protected var cumulativeBase = [];

	function initialize(data, base) {
		if (data.size() == 0) {
			throw new Lang.Exception(/* No data */);
		}

		if (base.size() == 0) {
			base = new [data.size()];
			for (var i = 0; i < base.size(); i++) {
				base[i] = 1;
			}
		}

		if (data.size() != base.size()) {
			throw new Lang.Exception(/* Data/base mismatch */);
		}

		// sort both `data` & `base` the same way: by increasing `data` value
		self.sortedData = self.insertionSort(data);
		var dataClone = [].addAll(data);
		for (var i = 0; i < self.sortedData.size(); i++) {
			var value = self.sortedData[i];
			var index = dataClone.indexOf(value);
			self.sortedBase.add(base[i]);
			// nullify value in data so it doesn't show up again if we have it more than once
			dataClone[index] = null;
		}

		// make base cumulative, so we can easily find requested quantile
		self.cumulativeBase = new [self.sortedBase.size()];
		for (var i = 0; i < self.sortedBase.size(); i++) {
			var previous = i > 0 ? self.cumulativeBase[i - 1] : 0;
			self.cumulativeBase[i] = previous + self.sortedBase[i];
		}
	}

	function insertionSort(array) {
		// turns out a recursive quicksort leads to Stack Overflow Error,
		// so here's a lesser sorting algorithm instead...
		for (var i = 0; i < array.size(); i++) {
			var value = array[i];

			var j;
			for (j = i - 1; j >= 0 && array[j] > value; j--) {
				array[j + 1] = array[j];
			}
			array[j + 1] = value;
		}
		return array;
	}

	function calculate(quantile) {
		if (quantile < 0 || quantile > 1) {
			throw new Lang.Exception(/* Quantile must be 0 <= x <= 1 */);
		}

		if (self.cumulativeBase[self.cumulativeBase.size() - 1] == 0) {
			return 0;
		}

		// determine index, based on cumulative base
		var cumul = quantile * self.cumulativeBase[self.cumulativeBase.size() - 1];
		var index = 0;
		for (var i = 0; i < self.cumulativeBase.size(); i++) {
			if (self.cumulativeBase[i] > cumul) {
				break;
			}
			index = i;
		}

		return self.sortedData[index];
	}

}