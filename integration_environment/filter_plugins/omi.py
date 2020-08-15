# Copyright: (c) 2020, Jordan Borean (@jborean93) <jborean93@gmail.com>
# MIT License (see LICENSE or https://opensource.org/licenses/MIT)

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type


def str_to_list(value, delimiter=','):
    if not isinstance(value, list):
        value = value.split(delimiter)

    return [v.strip() for v in value if v.strip()]


class FilterModule:

    def filters(self):
        return {
            'str_to_list': str_to_list
        }
