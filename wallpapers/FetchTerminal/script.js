const root = document.documentElement;

const userSettings = {
	dateformat: "mmddyyyy",
	appearance: {
		background: "#0d1110",
		text: "#e4edea",
	},
	volume: {
		showExtras: true, // bass/mid/treble sliders
		smoothness: 0.2,
	},
	times: [
		{ enabled: true, label: "HOME" },
		{ enabled: true, label: "CET", timezone: 1 },
		{ enabled: true, label: "UTC", timezone: 0 },
		{ enabled: true, label: "PST", timezone: -7 },
		{ enabled: true, label: "JST", timezone: 9 },
	],
	timers: [
		{ enabled: true, label: "", date: "" },
		{ enabled: true, label: "", date: "" },
		{ enabled: true, label: "", date: "" },
		{ enabled: true, label: "", date: "" },
		{ enabled: true, label: "", date: "" },
	],
};

let initialLoad = true;
let startTimestamp = null;

function waitForUptimeElement() {
	const uptimeElement = document.querySelector(".uptime");
	if (!uptimeElement) {
		requestAnimationFrame(waitForUptimeElement);
		return;
	}

	startTimestamp = new Date();

	setInterval(() => {
		uptimeElement.textContent = formatTime(Math.floor((new Date() - startTimestamp) / 1000));
		updateClocks();
		updateTimers();
		updateDate();
	}, 1000);
}

requestAnimationFrame(waitForUptimeElement);

window.wallpaperPropertyListener = {
	applyUserProperties: function (properties) {
		let shouldUpdateClock = false;
		let shouldUpdateTimer = false;
		let shouldUpdateMargin = false;

		if (initialLoad === true) {
			margins.top = parseInt(properties.shifttop.value);
			margins.bottom = parseInt(properties.shiftbottom.value);
			margins.right = parseInt(properties.shiftleft.value);
			gap = parseInt(properties.shiftgap.value);

			updateMargin();
			initialLoad = false;
		}

		if (properties.textsize) {
			root.style.setProperty("--p", `${properties.textsize.value}pt`);
		}

		if (properties.theme) {
			const theme = properties.theme.value;
			document.documentElement.setAttribute("data-theme", theme);
		}

		const colorKeys = [
			"black",
			"red",
			"green",
			"yellow",
			"blue",
			"magenta",
			"cyan",
			"white",
			"bright-black",
			"bright-red",
			"bright-green",
			"bright-yellow",
			"bright-blue",
			"bright-magenta",
			"bright-cyan",
			"bright-white",
		];

		colorKeys.forEach((key) => {
			if (properties[key]) {
				let [r, g, b] = properties[key].value.split(" ").map(Number);
				r = Math.round(r * 255);
				g = Math.round(g * 255);
				b = Math.round(b * 255);
				document.documentElement.style.setProperty(`--color-${key}`, `rgb(${r},${g},${b})`);
			}
		});

		if (properties.backgroundcolor) {
			let [r, g, b] = properties.backgroundcolor.value.split(" ").map(Number);
				r = Math.round(r * 255);
				g = Math.round(g * 255);
				b = Math.round(b * 255);
				document.documentElement.style.setProperty(`--color-bg`, `rgb(${r},${g},${b})`);
		}

		if (properties.textcolor) {
			let [r, g, b] = properties.textcolor.value.split(" ").map(Number);
				r = Math.round(r * 255);
				g = Math.round(g * 255);
				b = Math.round(b * 255);
				document.documentElement.style.setProperty(`--color-fg`, `rgb(${r},${g},${b})`);
		}

		if (properties.dateformat) {
			userSettings.dateformat = properties.dateformat.value;
			updateDate();
		}

		if (properties.showextras) {
			const value = properties.showextras.value;

			userSettings.volume.showExtras = properties.showextras.value;

			if (sliders) {
				if (value === false) {
					[sliders.bass, sliders.mid, sliders.treble].forEach((slider) => {
						slider.classList.add("hidden");
					});
				} else {
					[sliders.bass, sliders.mid, sliders.treble].forEach((slider) => {
						slider.classList.remove("hidden");
					});
				}
			}
		}
		if (properties.smoothness) userSettings.volume.smoothness = 1 - parseFloat(properties.smoothness.value);

		for (let i = 0; i <= 4; i++) {
			const timeProp = properties[`time${i}`];
			if (timeProp) {
				const newVal = timeProp.value;
				const element = document.querySelector(`.time${i}`);
				if (element) {
					element.classList.toggle("hidden", !newVal);
					if (newVal === true) shouldUpdateClock = true;
				}
				userSettings.times[i].enabled = newVal;
			}

			const labelProp = properties[`clabel${i}`];
			if (labelProp) {
				userSettings.times[i].label = labelProp.value;
			}

			const tzProp = properties[`timezone${i}`];
			if (tzProp) {
				userSettings.times[i].timezone = tzProp.value;
			}
		}

		for (let i = 0; i <= 4; i++) {
			const timerProp = properties[`timer${i}`];
			if (timerProp) {
				const newVal = timerProp.value;
				const element = document.querySelector(`.timer${i}`);
				if (element) {
					element.classList.toggle("hidden", !newVal);
					if (newVal === true) shouldUpdateTimer = true;
				}
				userSettings.timers[i].enabled = newVal;
			}

			const labelProp = properties[`tlabel${i}`];
			if (labelProp) {
				userSettings.timers[i].label = labelProp.value;
			}

			const dateProp = properties[`tdate${i}`];
			if (dateProp) {
				userSettings.timers[i].date = dateProp.value;
			}
		}

		if (properties.shiftleft) {
			margins.right = properties.shiftleft.value;
			shouldUpdateMargin = true;
		}

		if (properties.shifttop) {
			margins.top = properties.shifttop.value;
			shouldUpdateMargin = true;
		}

		if (properties.shiftbottom) {
			margins.bottom = properties.shiftbottom.value;
			shouldUpdateMargin = true;
		}

		if (properties.shiftgap) {
			gap = properties.shiftgap.value;
			shouldUpdateMargin = true;
		}

		if (shouldUpdateClock) updateClocks();
		if (shouldUpdateTimer) updateTimers();
		if (shouldUpdateMargin) updateMargin();
	},
};

let margins = {
	right: null,
	top: null,
	bottom: null,
};
let gap = null;

function updateMargin() {
	Object.keys(margins).forEach((margin) => {
		const val = parseInt(margins[margin]);
		if (!val) return document.querySelector(".terminal").style.setProperty(`margin-${margin}`, "");

		document.querySelector(".terminal").style.setProperty(`margin-${margin}`, `${val}px`);
	});

	const gapInt = parseInt(gap);

	if (isNaN(gapInt) || !gap) {
		document.querySelector(".terminal").style.setProperty("gap", "");
		document.querySelector(".terminal").style.setProperty("justify-content", "space-between");
	} else {
		document.querySelector(".terminal").style.setProperty("gap", `${gapInt}px`);
		document.querySelector(".terminal").style.setProperty("justify-content", "unset");
	}
}

function updateDate() {
	const element = document.querySelector(".dateDisplay");

	const now = new Date();

	const month = now.getMonth() + 1;
	const day = now.getDate();
	const year = now.getFullYear();

	const format = userSettings.dateformat;

	if (format === "ddmmyyyy") {
		element.textContent = `${day}/${month}/${year}`;
	} else if (format === "mmddyyyy") {
		element.textContent = `${month}/${day}/${year}`;
	} else if (format === "yyyymmdd") {
		element.textContent = `${year}/${month}/${day}`;
	}
}

function updateClocks() {
	const times = ["time0", "time1", "time2", "time3", "time4"];
	const now = new Date();

	times.forEach((time, id) => {
		const element = document.querySelector(`.${time}`);
		if (userSettings.times[id].enabled === false || !element) return;

		let date;
		if (id === 0) {
			date = new Date(now);
		} else {
			const utc = new Date(now.getTime() + now.getTimezoneOffset() * 60000);
			const offsetHours = userSettings.times[id].timezone;
			date = new Date(utc.getTime() + offsetHours * 60 * 60 * 1000);
		}

		const h = date.getHours().toString().padStart(2, "0");
		const m = date.getMinutes().toString().padStart(2, "0");
		const s = date.getSeconds().toString().padStart(2, "0");

		const hour12 = (date.getHours() % 12 || 12).toString().padStart(2, "0");
		const ampm = date.getHours() >= 12 ? "PM" : "AM";

		const time24 = `${h}:${m}:${s}`;
		const time12 = `${hour12}:${m}:${s} ${ampm}`;

		const localYear = now.getFullYear();
		const localMonth = now.getMonth();
		const localDate = now.getDate();

		const targetYear = date.getFullYear();
		const targetMonth = date.getMonth();
		const targetDate = date.getDate();

		let day = "TODAY";
		if (targetYear === localYear && targetMonth === localMonth && targetDate === localDate - 1) {
			day = "YESTERDAY";
		} else if (targetYear === localYear && targetMonth === localMonth && targetDate === localDate + 1) {
			day = "TOMORROW";
		}

		// Time progress and bar allocation
		const totalSeconds = 86400;
		const secondsPassed = date.getHours() * 3600 + date.getMinutes() * 60 + date.getSeconds();
		const progress = secondsPassed / totalSeconds;
		const percentage = Math.floor(progress * 100);

		const totalBars = 24;

		const morningRatio = 5 / 24;
		const noonRatio = 14 / 24;
		const nightRatio = 5 / 24;

		const rawMorning = totalBars * morningRatio;
		const rawNoon = totalBars * noonRatio;
		const rawNight = totalBars * nightRatio;

		let morningBarsMax = Math.floor(rawMorning);
		let noonBarsMax = Math.floor(rawNoon);
		let nightBarsMax = Math.floor(rawNight);

		let allocated = morningBarsMax + noonBarsMax + nightBarsMax;
		let remaining = totalBars - allocated;

		const remainders = [
			{ segment: "morning", remainder: rawMorning - morningBarsMax },
			{ segment: "noon", remainder: rawNoon - noonBarsMax },
			{ segment: "night", remainder: rawNight - nightBarsMax },
		];

		remainders.sort((a, b) => b.remainder - a.remainder);

		for (let i = 0; i < remaining; i++) {
			if (remainders[i % 3].segment === "morning") morningBarsMax++;
			else if (remainders[i % 3].segment === "noon") noonBarsMax++;
			else nightBarsMax++;
		}

		const filledBars = Math.floor(progress * totalBars);
		const morningBars = Math.min(filledBars, morningBarsMax);
		const noonBars = Math.min(Math.max(filledBars - morningBarsMax, 0), noonBarsMax);
		const nightBars = Math.min(Math.max(filledBars - morningBarsMax - noonBarsMax, 0), nightBarsMax);

		element.querySelector(".label").textContent = `[${userSettings.times[id].label}]`;
		element.querySelector(".day").textContent = day;
		element.querySelector(".time24").textContent = time24;
		element.querySelector(".time12").textContent = time12;

		element.querySelector(".morning").textContent = "|".repeat(morningBars);
		element.querySelector(".noon").textContent = "|".repeat(noonBars);
		element.querySelector(".night").textContent = "|".repeat(nightBars);
		element.querySelector(".percentage").textContent = `${percentage}%`;
	});
}

function updateTimers() {
	const now = new Date();

	userSettings.timers.forEach((timer, index) => {
		if (!timer.enabled) return;

		const element = document.querySelector(`.timer${index}`);
		if (!element) return;

		const parts = timer.date.split("/").map((x) => Number(x.trim()));
		let targetDate;
		let hasYear = parts.length === 3;

		if (hasYear) {
			const [day, month, year] = parts;
			if (isNaN(day) || isNaN(month) || isNaN(year)) {
				showInvalid(element, timer.label);
				return;
			}
			targetDate = new Date(year, month - 1, day);
		} else if (parts.length === 2) {
			const [day, month] = parts;
			if (isNaN(day) || isNaN(month)) {
				showInvalid(element, timer.label);
				return;
			}
			targetDate = new Date(now.getFullYear(), month - 1, day);
			if (targetDate < now) {
				targetDate.setFullYear(targetDate.getFullYear() + 1);
			}
		} else {
			showInvalid(element, timer.label);
			return;
		}

		if (isNaN(targetDate.getTime())) {
			showInvalid(element, timer.label);
			return;
		}

		const msInDay = 1000 * 60 * 60 * 24;
		const diff = Math.floor((targetDate - now) / msInDay);
		const diffAbs = Math.abs(diff);

		let typeText = "";
		let dayText = "";

		if (!hasYear) {
			typeText = "[COUNT_REP]";
			dayText = `${diff} DAYS LEFT`;
		} else if (diff > 0) {
			typeText = "[COUNT_DOWN]";
			dayText = `${diff} DAYS LEFT`;
		} else {
			typeText = "[COUNT_UP]";
			dayText = `${diffAbs} DAYS AGO`;
		}

		element.querySelector(".type").textContent = typeText;
		element.querySelector(".label").textContent = `[${timer.label}]`;
		element.querySelector(".days").textContent = dayText;

		const daysElement = element.querySelector(".days");
		daysElement.classList.remove("ansi-red", "ansi-green");
		daysElement.classList.add(typeText === "[COUNT_UP]" ? "ansi-green" : "ansi-red");
	});
}

function showInvalid(element, label) {
	element.querySelector(".type").textContent = "[INVALID]";
	element.querySelector(".label").textContent = `[${label}]`;
	element.querySelector(".days").textContent = "";
}

/* #region Audio */
const getSmoothness = () => userSettings.volume.smoothness;
const maxGreen = 15;
const maxYellow = 10;
const maxRed = 5;
const totalBars = maxGreen + maxYellow + maxRed;

const smoothed = {
	volume: 0,
	bass: 0,
	mid: 0,
	treble: 0,
};

let sliders = null;

function waitForSliders() {
	const volume = document.querySelector(".slider.volume");
	const bass = document.querySelector(".slider.bass");
	const mid = document.querySelector(".slider.mid");
	const treble = document.querySelector(".slider.treble");

	if (volume && bass && mid && treble) {
		sliders = { volume, bass, mid, treble };
		// 无 Wallpaper Engine 音频时初始化为 0，避免显示假满格
		updateSliderVisual(sliders.volume, 0);
		updateSliderVisual(sliders.bass, 0);
		updateSliderVisual(sliders.mid, 0);
		updateSliderVisual(sliders.treble, 0);
	} else {
		requestAnimationFrame(waitForSliders);
	}
}
waitForSliders();

function updateSliderVisual(slider, percent) {
	if (!slider) return;

	percent = Math.max(0, Math.min(percent, 100));

	const activeBars = Math.round((percent / 100) * totalBars);
	const greenBars = Math.min(activeBars, maxGreen);
	const yellowBars = Math.min(Math.max(activeBars - maxGreen, 0), maxYellow);
	const redBars = Math.min(Math.max(activeBars - maxGreen - maxYellow, 0), maxRed);

	slider.querySelector(".ansi-green").textContent = "|".repeat(greenBars).padEnd(maxGreen, " ");
	slider.querySelector(".ansi-yellow").textContent = "|".repeat(yellowBars).padEnd(maxYellow, " ");
	slider.querySelector(".ansi-red").textContent = "|".repeat(redBars).padEnd(maxRed, " ");
	slider.querySelector(".ansi-bright-black").textContent = `${percent}%`;
}

// audio listener（仅 Wallpaper Engine 提供，KDE 下缺失时跳过）
function wallpaperAudioListener(audioArray) {
	if (!sliders) return;

	const len = audioArray.length;
	const third = Math.floor(len / 3);

	const bassArray = audioArray.slice(0, third);
	const midArray = audioArray.slice(third, 2 * third);
	const trebleArray = audioArray.slice(2 * third);

	const maxBass = Math.max(...bassArray);
	const maxMid = Math.max(...midArray);
	const maxTreble = Math.max(...trebleArray);
	const maxVolume = Math.max(...audioArray);

	const SMOOTHING = getSmoothness();

	smoothed.bass = smoothed.bass * (1 - SMOOTHING) + maxBass * SMOOTHING;
	smoothed.mid = smoothed.mid * (1 - SMOOTHING) + maxMid * SMOOTHING;
	smoothed.treble = smoothed.treble * (1 - SMOOTHING) + maxTreble * SMOOTHING;
	smoothed.volume = smoothed.volume * (1 - SMOOTHING) + maxVolume * SMOOTHING;

	if (userSettings.volume.showExtras) {
		updateSliderVisual(sliders.bass, Math.floor(smoothed.bass * 100));
		updateSliderVisual(sliders.mid, Math.floor(smoothed.mid * 100));
		updateSliderVisual(sliders.treble, Math.floor(smoothed.treble * 100));
	}

	updateSliderVisual(sliders.volume, Math.floor(smoothed.volume * 100));
}

if (window.wallpaperRegisterAudioListener) {
	window.wallpaperRegisterAudioListener(wallpaperAudioListener);
}
/* #endregion */

/* #region Media */

function wallpaperMediaPropertiesListener(event) {
	const title = event.title;
	const artist = event.artist;
	const album = event.albumTitle;

	document.querySelector(".currentTitle").textContent = title;
	document.querySelector(".currentArtist").textContent = artist;
	document.querySelector(".currentAlbum").textContent = album;

	document.querySelector(".playing-song .text").textContent = artist || title ? `${artist} - ${title}` : "";
}

if (window.wallpaperRegisterMediaPropertiesListener) {
	window.wallpaperRegisterMediaPropertiesListener(wallpaperMediaPropertiesListener);
}

function wallpaperMediaTimelineListener(event) {
	const duration = event.duration;
	const position = event.position;

	document.querySelector(".currentTime").textContent = formatTime(position);
	document.querySelector(".playing-song .time").textContent = `[${formatTime(position)}/${formatTime(duration)}]`;
}

if (window.wallpaperRegisterMediaTimelineListener) {
	window.wallpaperRegisterMediaTimelineListener(wallpaperMediaTimelineListener);
}

function wallpaperMediaPlaybackListener(event) {
	const element = document.querySelector(".playing-song .status");

	if (event.state !== window.wallpaperMediaIntegration.PLAYBACK_PLAYING) {
		element.textContent = "Idle:";
	} else {
		element.textContent = "Playing:";
	}
}
if (window.wallpaperRegisterMediaPlaybackListener) {
	window.wallpaperRegisterMediaPlaybackListener(wallpaperMediaPlaybackListener);
}

/* #endregion */

function formatTime(totalSeconds) {
	if (isNaN(totalSeconds) || totalSeconds < 0) {
		return "00:00";
	}

	const days = Math.floor(totalSeconds / 86400);
	const hours = Math.floor((totalSeconds % 86400) / 3600);
	const minutes = Math.floor((totalSeconds % 3600) / 60);
	const seconds = totalSeconds % 60;

	const padDouble = (num) => String(num).padStart(2, "0");

	let timeStr = "";

	if (days > 0) {
		timeStr += `${days}:`;
	}
	if (days > 0 || hours > 0) {
		timeStr += `${padDouble(hours)}:`;
	}
	timeStr += `${padDouble(minutes)}:${padDouble(seconds)}`;

	return timeStr;
}
