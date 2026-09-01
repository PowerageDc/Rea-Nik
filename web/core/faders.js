// core/faders.js — arrastre de faders de volumen y de sends.
// Depende de config.js (NIK_FADER_DBLTAP_MS), core/state.js (mouseDown,
// volOutputdB, thisSendTrackId, sendOutputdB, faderLastTapAr) y de wwr_req
// (global, definido en main.js).

function mouseDownEventHandler(msg) {
    return function (e) {
        if (typeof e == 'undefined') e = event;
        if (e.preventDefault) e.preventDefault();
        wwr_req(msg);
        return false;
    }
}

function mouseUpHandler(event) {
    if (mouseDown == 1 && volOutputdB != null) {
        wwr_req("SET/TRACK/" + this.id + "/VOL/" + volOutputdB + "e")
    }
    volOutputdB = null;
    mouseDown = 0;
}
function mouseDownHandler(event, target) { mouseDown = 1; }
function mouseLeaveHandler(event) { mouseDown = 0; }
function mouseMoveHandler(event) {
    if (mouseDown != 1) { return; }
    else {
        var volTrackWidth = (this.getBoundingClientRect()["width"]);
        var volThumbWidth = volTrackWidth * 0.14375;
        var volThumbTrackWidth = (volTrackWidth - volThumbWidth);
        var volThumbTrackLEdge = this.getBoundingClientRect()["left"];
        offsetX = (event.pageX - volThumbTrackLEdge - (volThumbWidth / 2));

        if (event.changedTouches != undefined) { //we're doing touch stuff
            offsetX = (event.changedTouches[0].pageX - volThumbTrackLEdge - (volThumbWidth / 2));
        }
        if (offsetX < 0) { offsetX = 0 };
        if (offsetX > volThumbTrackWidth) { offsetX = volThumbTrackWidth };

        var volThumb = this.firstChild.getElementsByClassName("fader")[0];
        var offsetX320 = offsetX * (320 / volTrackWidth);
        var vteMove320 = "translate(" + offsetX320 + " 0)";
        volThumb.setAttributeNS(null, "transform", vteMove320);
        var volOutput = (offsetX / volThumbTrackWidth);
        volOutputdB = Math.pow(volOutput, 4) * 4;
        wwr_req("SET/TRACK/" + this.id + "/VOL/" + volOutputdB)
    }
}

function sendMouseMoveHandler(event) {
    if (mouseDown != 1) { return; }
    else {
        var sendTrackWidth = this.getElementsByClassName("sendBg")[0].getBoundingClientRect()["width"];
        var sendThumbWidth = this.getElementsByClassName("sendBg")[0].getBoundingClientRect()["height"];
        var sendThumbTrackWidth = (sendTrackWidth - sendThumbWidth);
        var sendThumbTrackLEdge = this.getElementsByClassName("sendBg")[0].getBoundingClientRect()["left"];

        offsetX = event.pageX - sendThumbTrackLEdge - (sendThumbWidth / 2);
        if (event.changedTouches != undefined) { //we're doing touch stuff
            offsetX = (event.changedTouches[0].pageX - sendThumbTrackLEdge - (sendThumbWidth / 2));
        }
        if (offsetX < 0) { offsetX = 0 };
        if (offsetX > sendThumbTrackWidth) { offsetX = sendThumbTrackWidth };

        var offsetX262 = offsetX * (262 / sendTrackWidth) + 26;
        var sendThumb = this.getElementsByClassName("sendThumb")[0];
        sendThumb.setAttributeNS(null, "cx", offsetX262);
        var sendLine = this.getElementsByClassName("sendLine")[0];
        sendLine.setAttributeNS(null, "x2", offsetX262);

        var sendOutput = (offsetX / sendThumbTrackWidth);
        sendOutputdB = Math.pow(sendOutput, 4) * 4;
        thisSendTrackId = (this.parentNode.id).slice(10);
        wwr_req("SET/TRACK/" + thisSendTrackId + "/SEND/" + this.id + "/VOL/" + sendOutputdB)
    }
}

function faderResetToUnity(content, thumb) {
    var vteMove = "translate(194.68 0)";
    thumb.setAttributeNS(null, "transform", vteMove);
    wwr_req("SET/TRACK/" + content.id + "/VOL/1e");
    mouseDown = 1;
    window.setTimeout(function () { mouseDown = 0; }, 400);
}

function faderCheckDoubleTap(content, thumb) {
    var now = (new Date).getTime();
    var key = content.id;
    var last = faderLastTapAr[key] || 0;
    if ((now - last) < NIK_FADER_DBLTAP_MS) {
        faderLastTapAr[key] = 0;
        faderResetToUnity(content, thumb);
        return true;
    }
    faderLastTapAr[key] = now;
    return false;
}

function volFaderConect(content, thumb) {
    content.addEventListener("mousemove", mouseMoveHandler, false);
    content.addEventListener("touchmove", mouseMoveHandler, false);
    content.addEventListener("mouseleave", mouseLeaveHandler, false);
    content.addEventListener("mouseup", mouseUpHandler, false);
    content.addEventListener("touchend", mouseUpHandler, false);
    thumb.addEventListener("mousedown", function (event) {
        if (faderCheckDoubleTap(content, thumb)) { if (event.preventDefault) event.preventDefault(); return; }
        mouseDownHandler(event, event.srcElement);
    }, false);
    thumb.addEventListener('touchstart', function (event) {
        if (event.touches.length > 0) {
            if (faderCheckDoubleTap(content, thumb)) { event.preventDefault(); return; }
            mouseDownHandler(event, event.srcElement);
        }
        event.preventDefault();
    }, false);
}

function sendMouseUpHandler(event) {
    wwr_req("SET/TRACK/" + thisSendTrackId + "/SEND/" + this.id + "/VOL/" + sendOutputdB + "e");
    mouseDown = 0;
}