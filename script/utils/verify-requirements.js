var path = require('path');
var fs = require('fs');
var childProcess = require('child_process');

var pythonExecutable = process.env.PYTHON;

module.exports = function(cb) {
  verifyNode(function(error, nodeSuccessMessage) {
    if (error) {
      cb(error);
      return;
    }

    verifyPython27(function(error, pythonSuccessMessage) {
      cb(error, (nodeSuccessMessage + "\n" + pythonSuccessMessage).trim());
    });
  });

};

function verifyNode(cb) {
  var nodeVersion = process.versions.node;
  var versionArray = nodeVersion.split('.');
  var nodeMajorVersion = +versionArray[0];
  var nodeMinorVersion = +versionArray[1];
  if (nodeMajorVersion === 0 && nodeMinorVersion < 10) {
    error = "node v0.10 is required to build Atom.";
    cb(error);
  }
  else {
    cb(null, "Node: v" + nodeVersion);
  }
}

function verifyPython27(cb) {
  if (process.platform == 'win32') {
    if (!pythonExecutable) {
      var systemDrive = process.env.SystemDrive || 'C:\\';
      pythonExecutable = path.join(systemDrive, 'Python27', 'python.exe');

      if (!fs.existsSync(pythonExecutable)) {
        pythonExecutable = 'python';
      }
    }

    checkPythonVersion(pythonExecutable, cb);
  }
  else {
    cb(null, '');
  }
}

function checkPythonVersion (python, cb) {
  var pythonHelpMessage = "Set the PYTHON env var to '/path/to/Python27/python.exe' if your python is installed in a non-default location.";

  childProcess.execFile(python, ['-c', 'import platform; print(platform.python_version());'], { env: process.env }, function (err, stdout) {
    if (err) {
      error = "Python 2.7 is required to build Atom. An error (" + err + ") occured when checking the version of '" + python + "'. ";
      error += pythonHelpMessage;
      cb(error);
      return;
    }

    var version = stdout.trim();
    if (~version.indexOf('+')) {
      version = version.replace(/\+/g, '');
    }
    if (~version.indexOf('rc')) {
      version = version.replace(/rc(.*)$/ig, '');
    }

    // Atom requires python 2.7 or higher (but not python 3) for node-gyp
    var versionArray = version.split('.').map(function(num) { return +num; });
    var goodPythonVersion = (versionArray[0] === 2 && versionArray[1] >= 7);
    if (!goodPythonVersion) {
      error = "Python 2.7 is required to build Atom. '" + python + "' returns version " + version + ". ";
      error += pythonHelpMessage;
      cb(error);
      return;
    }

    // Finally, if we've gotten this far, callback to resume the install process.
    cb(null, "Python: v" + version);
  });
}
