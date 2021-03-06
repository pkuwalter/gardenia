// Copyright 2016, National University of Defense Technology
// Authors: Xuhao Chen <cxh@illinois.edu>
#include <stdio.h>
#define SPMV_VARIANT "texture"
#include "spmv.h"
#include "cuda_launch_config.hpp"
#include "cutil_subset.h"
#include "timer.h"

// CSR SpMV kernels based on a scalar model (one thread per row)
// spmv_csr_scalar_tex
//   Same as spmv_csr_scalar, except x is accessed via texture cache.
texture<float,1> tex_x;
void bind_x(const float * x) { CUDA_SAFE_CALL(cudaBindTexture(NULL, tex_x, x)); }
void unbind_x(const float * x) { CUDA_SAFE_CALL(cudaUnbindTexture(tex_x)); }

__global__ void spmv_csr_scalar_kernel(int m, const IndexT * Ap,  const IndexT * Aj, const ValueT * Ax, const ValueT * x, ValueT * y) {
	int row = blockIdx.x * blockDim.x + threadIdx.x;
	if (row < m) {
		ValueT sum = y[row];
		int row_begin = Ap[row];
		int row_end = Ap[row+1];
		for (int offset = row_begin; offset < row_end; offset ++) {
			sum += Ax[offset] * tex1Dfetch(tex_x, Aj[offset]);
		}
		y[row] = sum;
	}
}

void SpmvSolver(int num_rows, int nnz, int *h_Ap, int *h_Aj, ValueT *h_Ax, ValueT *h_x, ValueT *h_y, int *degree) { 
	//print_device_info(0);
	Timer t;
	int *d_Ap, *d_Aj;
	CUDA_SAFE_CALL(cudaMalloc((void **)&d_Ap, (num_rows + 1) * sizeof(int)));
	CUDA_SAFE_CALL(cudaMalloc((void **)&d_Aj, nnz * sizeof(int)));
	CUDA_SAFE_CALL(cudaMemcpy(d_Ap, h_Ap, (num_rows + 1) * sizeof(int), cudaMemcpyHostToDevice));
	CUDA_SAFE_CALL(cudaMemcpy(d_Aj, h_Aj, nnz * sizeof(int), cudaMemcpyHostToDevice));
	ValueT *d_Ax, *d_x, *d_y;
	CUDA_SAFE_CALL(cudaMalloc((void **)&d_Ax, sizeof(ValueT) * nnz));
	CUDA_SAFE_CALL(cudaMalloc((void **)&d_x, sizeof(ValueT) * num_rows));
	CUDA_SAFE_CALL(cudaMalloc((void **)&d_y, sizeof(ValueT) * num_rows));
	CUDA_SAFE_CALL(cudaMemcpy(d_Ax, h_Ax, nnz * sizeof(ValueT), cudaMemcpyHostToDevice));
	CUDA_SAFE_CALL(cudaMemcpy(d_x, h_x, num_rows * sizeof(ValueT), cudaMemcpyHostToDevice));
	CUDA_SAFE_CALL(cudaMemcpy(d_y, h_y, num_rows * sizeof(ValueT), cudaMemcpyHostToDevice));
	int nthreads = BLOCK_SIZE;
	int nblocks = (num_rows - 1) / nthreads + 1;
	printf("Launching CUDA SpMV solver (%d CTAs, %d threads/CTA) ...\n", nblocks, nthreads);

	t.Start();
	bind_x(d_x);
	spmv_csr_scalar_kernel <<<nblocks, nthreads>>> (num_rows, d_Ap, d_Aj, d_Ax, d_x, d_y);   
	CudaTest("solving failed");
	unbind_x(d_x);
	CUDA_SAFE_CALL(cudaDeviceSynchronize());
	t.Stop();

	printf("\truntime [%s] = %f ms.\n", SPMV_VARIANT, t.Millisecs());
	CUDA_SAFE_CALL(cudaMemcpy(h_y, d_y, sizeof(ValueT) * num_rows, cudaMemcpyDeviceToHost));
	CUDA_SAFE_CALL(cudaFree(d_Ap));
	CUDA_SAFE_CALL(cudaFree(d_Aj));
	CUDA_SAFE_CALL(cudaFree(d_Ax));
	CUDA_SAFE_CALL(cudaFree(d_x));
	CUDA_SAFE_CALL(cudaFree(d_y));
}

