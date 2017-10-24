#!/usr/bin/env python
# coding: utf-8

import logging

import numpy as np

LOG = logging.getLogger(__name__)


class BlockToeplitzMatrix:
    """A block Toeplitz matrix stored as a list of matrices (the blocks)."""

    def __init__(self, blocks):

        self.blocks = blocks
        self.dtype = blocks[0].dtype

        for block in blocks:
            assert len(block.shape) == 2
            assert block.shape[0] == self.block_size
            assert block.shape[1] == self.block_size
            assert block.dtype == self.dtype

    @property
    def nb_blocks(self):
        return len(self.blocks)

    @property
    def block_size(self):
        return self.blocks[0].shape[0]

    def full_matrix(self):
        full_matrix = np.empty((self.nb_blocks*self.block_size,
                                self.nb_blocks*self.block_size,
                                ), dtype=self.dtype)

        for i in range(self.nb_blocks):
            for j in range(self.nb_blocks):
                full_matrix[(slice(i*self.block_size, (i+1)*self.block_size),
                             slice(j*self.block_size, (j+1)*self.block_size),
                             )] = self.blocks[abs(j-i)]

        return full_matrix


def solve(A, b):
    """Solve the linear system Ax = b"""
    if isinstance(A, BlockToeplitzMatrix):
        if A.nb_blocks == 2:
            # Not implemented yet
            return np.linalg.solve(A, b)

        else:
            # Not implemented yet
            return np.linalg.solve(A, b)

    elif isinstance(A, np.ndarray):
        return np.linalg.solve(A, b)

    else:
        raise ValueError(f"Unreognized type of {A} in solve")
