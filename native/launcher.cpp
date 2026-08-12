#include <Python.h>
#include <iostream>

int main(int argc, char *argv[]) {
    PyStatus status;
    PyConfig config;
    PyConfig_InitPythonConfig(&config);

    // Set program name
    status = PyConfig_SetBytesString(&config, &config.program_name, argv[0]);
    if (PyStatus_Exception(status)) {
        std::cerr << "Failed to set program name.\n";
        return 1;
    }

    // Check if we are in a virtual environment
    const char* venv = std::getenv("VIRTUAL_ENV");
    const char* conda_env = std::getenv("CONDA_PREFIX");
    if (venv) {
        status = PyConfig_SetBytesString(&config, &config.home, venv);
        if (PyStatus_Exception(status)) {
            std::cerr << "Failed to set virtual env python home.\n";
            return 1;
        }
    } else if (conda_env) {
        status = PyConfig_SetBytesString(&config, &config.home, conda_env);
        if (PyStatus_Exception(status)) {
            std::cerr << "Failed to set conda env python home.\n";
            return 1;
        }
    } else {
#ifdef PYTHON_PREFIX
        // Fallback to compile-time prefix
        status = PyConfig_SetBytesString(&config, &config.home, PYTHON_PREFIX);
        if (PyStatus_Exception(status)) {
            std::cerr << "Failed to set compile-time python home.\n";
            return 1;
        }
#endif
    }

    // Read sys.argv
    status = PyConfig_SetBytesArgv(&config, argc, argv);
    if (PyStatus_Exception(status)) {
        std::cerr << "Failed to set argv.\n";
        return 1;
    }

    status = Py_InitializeFromConfig(&config);
    if (PyStatus_Exception(status)) {
        std::cerr << "Failed to initialize Python.\n";
        return 1;
    }
    PyConfig_Clear(&config);

    FILE* file = fopen("main.py", "r");
    if (file) {
        // Ensure the current directory is in sys.path so local modules are found
        PyRun_SimpleString("import sys; sys.path.insert(0, '')");
        PyRun_SimpleFile(file, "main.py");
        fclose(file);
    } else {
        std::cerr << "Failed to open main.py\n";
        return 1;
    }

    if (Py_FinalizeEx() < 0) {
        return 120;
    }

    return 0;
}
