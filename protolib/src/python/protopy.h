#ifndef _PROTO_PYTHON
#define _PROTO_PYTHON

#define PY_SSIZE_T_CLEAN
#include <Python.h>
//#include <cstring>

extern "C" {

static PyObject* ProtoError;  // Custom exception type

}  // end extern "C"

#endif // !_PROTO_PYTHON
