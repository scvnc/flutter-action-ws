#!/bin/bash

find -name '*.dart' | entr pub run test ${@}