// MIT License
//
// Copyright 2017 Mystic Pants Pty Ltd
//
// SPDX-License-Identifier: MIT
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
// EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
// OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.


// these values can be found at https://media.digikey.com/pdf/Data%20Sheets/Radiocrafts%20PDFs/RC16yyyy-SIG_UM_Rev1.9_6-10-16.pdf
const RC1692HP_TEMPERATURE_OFFSET = 128;
const RC1692HP_BATTERY_COEFFICIENT = 0.030;

const RC1692HP_MAX_MESSAGE_LENGTH = 12;
const RC1692HP_ID_BYTES = 4;
const RC1692HP_PAC_BYTES = 8;

// Default parameters
const RC1692HP_DEFAULT_BAUD_RATE = 19200;
const RC1692HP_DEFAULT_WORD_SIZE = 8;
const RC1692HP_DEFAULT_STOP_BIT = 1;
const RC1692HP_DEFAULT_TIME_OUT = 1.0;
const RC1692HP_DEFAULT_DELAY = 2.0;
const RC1692HP_DEFAULT_PARITY = 0; // see https://electricimp.com/docs/api/hardware/uart/configure/
const RC1692HP_DEFAULT_FLAGS = 4; // see https://electricimp.com/docs/api/hardware/uart/configure/
const RC1692HP_DEFAULT_SHOULD_LOG = 1;

// Error messages
const RC1692HP_ERROR_UNSUPPORTED_MODE = "Unsupported mode, currently only supports congfig and normal modes";
const RC1692HP_ERROR_MESSAGE_LENGTH_TOO_LONG = "Message length exceeds 12 characters";
const RC1692HP_ERROR_TIMED_OUT = "Time out";

enum RC1692HP_MODE {
    CONFIG ,
    NORMAL
}




class RC1692HP {

    _uart = null;
    _inputBuffer = null;
    _queue = null;
    _timeout = null;
    _delay = null;
    _shouldLog = null;
    _currentMode = null;
    _timeoutTimer = null;
    _currentCommand = null;
    _result = null;
    _resultHandler = null;

    static COMMANDS = {

        "memory": {
            "cmd": "M",
            "length": 1,
        },
        "readId": {
            "cmd": "9",
            "length": 13
        },
        "exitToNormal": {
            "cmd": "X",
            "length": 0
        },
        "configMode": {
            "cmd": "\0",
            "length": 1
        },
        "signalStrength": {
            "cmd": "S",
            "length": 2
        },
        "tempMonitor": {
            "cmd": "U",
            "length": 2
        },
        "batMonitor": {
            "cmd": "V",
            "length": 2
        },
        "memoryRead": {
            "cmd": "Y",
            "length": 1
        },
        "sigFoxMode": {
            "cmd": "F",
            "length": 1
        },
        "readConfig": {
            "cmd": "READCONFIG",
            "length": 2
        },
        "config": {
            "cmd": "CONFIG",
            "length": 1
        },
        "message": {
            "cmd": "MESSAGE",
            "length": 0
        },
        "modeSwitch": {
            "cmd": "MODESWITCH",
            "length": 1
        }

        /*
        "M" : 1,	// Memory configuration menu
        "9" : 13,	// Read id
        "X" : 0,	// Exit to normal operation
        "\0": 1,	// Config Mode
        "S" : 2,	// Signal Strength
        "U" : 2,	// Temperature monitoring
        "V" : 2,	// Battery monitoring
        "Y" : 1,	// memory read
        "F" : 1,	// SIGFOX mode
        "READCONFIG" : 2,
        "CONFIG" : 1,
        "MESSAGE" : 0,
        "MODESWITCH" : 1
        */
    };

    constructor(uart, params = {}){

        // uart configure params
        local baudRate = ("baudRate" in params) ? params.baudRate : RC1692HP_DEFAULT_BAUD_RATE;
        local wordSize = ("wordSize" in params) ? params.wordSize : RC1692HP_DEFAULT_WORD_SIZE;
        local parity = ("parity" in params) ? params.parity : RC1692HP_DEFAULT_PARITY;
        local stopBit = ("stopBit" in params) ? params.stopBit : RC1692HP_DEFAULT_STOP_BIT;
        local flags = ("flags" in params) ? params.flags : RC1692HP_DEFAULT_FLAGS;

        // configure internal variables
        _timeout = ("timeout" in params) ? params.timeout : RC1692HP_DEFAULT_TIME_OUT;
        _delay = ("delay" in params) ? params.delay : RC1692HP_DEFAULT_DELAY;
        _shouldLog = ("shouldLog" in params) ? params.shouldLog : RC1692HP_DEFAULT_SHOULD_LOG;
        _queue = [];
        _currentMode = RC1692HP_MODE.NORMAL;
        _result = {};
        _uart = uart;
        _inputBuffer = blob();

        // configure uart based on params
        _uart.configure(baudRate, wordSize, parity, stopBit, flags, _onInputHandler.bindenv(this));


    }


	//--------------------------------------------------------------------------
	//		switchMode: switches the mode of operation
	//		Returns: null
	//		Parameters:
	// 			mode - the mode of operation you want to switch to
	//--------------------------------------------------------------------------
    function switchMode(mode) {

        _enqueue(function() {

            switch(mode) {
                case RC1692HP_MODE.CONFIG:
                    _sendData(COMMANDS.configMode);
                    //_sendData("\0");
                    break;

                case RC1692HP_MODE.NORMAL:
                    _currentMode = mode;
                    _sendData(COMMANDS.exitToNormal);
                    //_sendData("X");
                    break;

                default :
                    throw RC1692HP_ERROR_UNSUPPORTED_MODE;
            }
        }.bindenv(this));
    }



	//--------------------------------------------------------------------------
	//		configure:  configures parameters stored in non-volatile memory
    //
	//		Returns: null
	//		Parameters:
	// 			 address - memory address of parameter you want to configure
    //           value - new value for the the parameter that you want to configure
	//--------------------------------------------------------------------------
    function configure(address, value) {

        _enqueue(function() {

            _sendData(COMMANDS.memory);
        }.bindenv(this));
        _enqueue(function() {

	        local query = blob();
            query.writen(address,'b');
            query.writen(value,'b');
            query.writen(0xff,'b');
            _sendData(query, COMMANDS.config);
        }.bindenv(this));
    }



	//--------------------------------------------------------------------------
	//		sendMessage: Sends a message to RC1692HP Sigfox
	//		Returns: null
	//		Parameters:
	// 			 message - the message that you want to send
	//--------------------------------------------------------------------------
    function sendMessage(message) {

        _enqueue(function() {

            local payload = blob();
            switch(typeof message) {

                case "blob" :
                    payload.writen(message.len(), 'b');
                    payload.writeblob(message);
                    break;

                case "string" :
                    payload.writen(message.len(), 'b');
                    payload.writestring(message);
                    break;

                default :
                    throw "type " + typeof message + " is not supported";
            }
            if (message.len() > RC1692HP_MAX_MESSAGE_LENGTH) {
                throw RC1692HP_ERROR_MESSAGE_LENGTH_TOO_LONG;
            }
            _sendData(payload, COMMANDS.message);
        }.bindenv(this));
    }



	//--------------------------------------------------------------------------
	//		readID: Reads the devcie ID and the PAC number
	//		Returns: null
	//		Parameters:
	// 			callback(optional) - callback to be executed once a result is returned
	//--------------------------------------------------------------------------
    function readID(callback = null) {

        _enqueue(function() {

            _sendData(COMMANDS.readId);
            _resultHandler = callback;
        }.bindenv(this));
    }



	//--------------------------------------------------------------------------
	//		readRSSI: Reads the signal Strength of a detected signal or valid packet
	//		Returns: null
	//		Parameters:
	// 			callback(optional) - callback to be executed once a result is returned
	//--------------------------------------------------------------------------
    function readRSSI(callback = null) {

        _enqueue(function(){

            _sendData(COMMANDS.signalStrength);
            _resultHandler = callback;
        }.bindenv(this));
    }



	//--------------------------------------------------------------------------
	//		readTemperature: Reads the temperature of the RC1692HP Sigfox
	//		Returns: null
	//		Parameters:
	// 			callback(optional) - callback to be executed once a result is returned
	//--------------------------------------------------------------------------
    function readTemperature(callback = null) {

        _enqueue(function() {

            _sendData(COMMANDS.tempMonitor);
            _resultHandler = callback;
        }.bindenv(this));
    }



	//--------------------------------------------------------------------------
	//		readBattery: Reads the battery voltage of the RC1692HP Sigfox
	//		Returns: null
	//		Parameters:
	// 			callback(optional) - callback to be executed once a result is returned
	//--------------------------------------------------------------------------
    function readBattery(callback = null) {

        _enqueue(function() {

            _sendData(COMMANDS.batMonitor);
            _resultHandler = callback;
        }.bindenv(this));
    }



	//--------------------------------------------------------------------------
	//		readConfigurationAt: Reads the parameters values stored in non-volatile memory
	//		Returns: null
	//		Parameters:
	// 			address - memory address of parameter you want to read
	//			callback(optional) -  callback to be executed once a result is returned
	//--------------------------------------------------------------------------
    function readConfigurationAt(address, callback = null) {

        _enqueue(function() {

            _sendData(COMMANDS.memoryRead);
        }.bindenv(this));
        _enqueue(function() {

            _sendData(address, COMMANDS.readConfig);
            _resultHandler = callback;
        }.bindenv(this));
    }



	//--------------------------------------------------------------------------
	//		_onInputHandler: Handles receiving of data on the UART channel
	//		Returns: null
	//		Parameters: null
	//--------------------------------------------------------------------------
    function _onInputHandler() {

        _inputBuffer.writeblob(_uart.readblob());

        if(_currentCommand != null) {
            if (_inputBuffer.len() >= _currentCommand.length) {
                _cancelTimer();
                _log(_inputBuffer, "receiving data : ");
                _processInput(_currentCommand.cmd);
                _invokeResultHandler();
                _cleanUp();
                _nextInQueue();
            }
        }

    }



	//--------------------------------------------------------------------------
	//		_cancelTimer: cancels the timer
	//		Returns: null
	//		Parameters: null
	//--------------------------------------------------------------------------
    function _cancelTimer() {

        if (_timeoutTimer) {
            imp.cancelwakeup(_timeoutTimer);
            _timeoutTimer = null;
        }
    }



	//--------------------------------------------------------------------------
	//		_processInput: Organises data from packets
	//		Returns: null
	//		Parameters:
	// 			command - the command that corresponds to the packet
	//--------------------------------------------------------------------------
    function _processInput(command) {

        _inputBuffer.seek(0);
        switch(command) {

            case "9" :
                _result.ID <- _convertBlobToString(_inputBuffer.readblob(RC1692HP_ID_BYTES), "%02X ");
                _result.PAC <- _convertBlobToString(_inputBuffer.readblob(RC1692HP_PAC_BYTES), "%02X ");
                break;

            case "\0":
                _currentMode = RC1692HP_MODE.CONFIG;
                break;

            case "S" :
                _result.RSSI <- format("%u", _inputBuffer.readn('b'));
                break;

            case "U" :
                _result.temperature <- format("%u", _inputBuffer.readn('b') - RC1692HP_TEMPERATURE_OFFSET);
                break;

            case "V" :
                _result.battery <- format("%.2f", _inputBuffer.readn('b') * RC1692HP_BATTERY_COEFFICIENT);
                break;

            case "READCONFIG":
                _result.value <- format("%u", _inputBuffer.readn('b'));
                break;
        }
    }



	//--------------------------------------------------------------------------
	//		_enqueue: adds the action to the queue. If the queue was empty executes
    //                  the action
	//		Returns: null
	//		Parameters:
	// 			action - the code to be executed
	//--------------------------------------------------------------------------
    function _enqueue(action) {

        _queue.push(action);
        if (_queue.len() == 1) {
            imp.wakeup(0, function() {
                action();
            }.bindenv(this));
        }
    }



	//--------------------------------------------------------------------------
	//		_nextInQueue: deletes the previous action and runs the next action
	//		Returns: null
	//		Parameters: null
	//--------------------------------------------------------------------------
    function _nextInQueue() {

        _queue.remove(0);
        if (_queue.len() > 0) {
            local delay = (_currentMode == RC1692HP_MODE.NORMAL) ? _delay : 0;
            imp.wakeup(delay, function() {
                _queue[0]();
            }.bindenv(this));
        }
    }



	//--------------------------------------------------------------------------
	//		_cleanUp: cleans up after a action reseting some variables
	//		Returns: null
	//		Parameters: null
	//--------------------------------------------------------------------------
    function _cleanUp() {

        _result = {};
        _inputBuffer = blob();
        _currentCommand = null;
        _resultHandler = null;
    }



	//--------------------------------------------------------------------------
	//		_sendData: sends data via UART to RC1692HP Sigfox
	//		Returns: null
	//		Parameters:
	// 			data - data to be sent
	//			comment(optional) -
	//--------------------------------------------------------------------------
    function _sendData(data, comment = null) {

        _currentCommand = comment ? comment : data;
        if(_currentCommand == comment) {
            _uart.write(data);
        } else {
            _uart.write(data.cmd);
        }

        _log(data, "sending data : ");
        // check if it expects any response . if not, fire the next action in the queue;
        //server.log(COMMANDS[_currentCommand]);
        if (_currentCommand.length == 0) {
            _cleanUp();
            _nextInQueue();
        }
        else {
            _timeoutTimer = imp.wakeup(_timeout, function() {
                _result.error <- RC1692HP_ERROR_TIMED_OUT;
                throw RC1692HP_ERROR_TIMED_OUT
                //_invokeResultHandler();
            }.bindenv(this));
        }

    }



	//--------------------------------------------------------------------------
	//		_log: logs events
	//		Returns: null
	//		Parameters:
	// 			 message - the message to be logged
	//			 prefix(optional) - a prefix to be put in front the log
	//--------------------------------------------------------------------------
    function _log(message, prefix = "") {

        if (_shouldLog) {
            switch(typeof message){
                case "blob":
                    message = _convertBlobToString(message, "0x%02X ");
                    break;
                case "string":
                    message = format("%s", message);
            }
            server.log(prefix + message);
        }
    }



	//--------------------------------------------------------------------------
	//		_convertBlobToString: coverts a blob to a string
	//		Returns: null
	//		Parameters:
    //            blob - the blob to be converted
    //            stringFormat - the format that the string should take
	//--------------------------------------------------------------------------
    function _convertBlobToString(blob, stringFormat) {

        local string = "";
        foreach (byte in blob) {
            string += format(stringFormat, byte);
        }
        return string;
    }



	//--------------------------------------------------------------------------
	//		_invokeResultHandler: invokes the result handler
	//		Returns: null
	//		Parameters: null
	//--------------------------------------------------------------------------
    function _invokeResultHandler() {

        if (_resultHandler) {
            _resultHandler(_result);
        }
        /*
        else if ("error" in _result) {
             throw _result.error;
        }*/
    }

}
