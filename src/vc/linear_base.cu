// Copyright 2016, National University of Defense Technology
// Authors: Xuhao Chen <cxh@illinois.edu> and Pingfan Li <lipingfan@163.com>
#define VC_VARIANT "linear_base"
#include <cub/cub.cuh>
#include "vc.h"
#include "timer.h"
#include "cuda_launch_config.hpp"
#include "cutil_subset.h"
//#include <thrust/sequence.h>
//#include <thrust/reduce.h>
//#include <thrust/execution_policy.h>
#include "worklistc.h"

__global__ void first_fit(int m, int *row_offsets, int *column_indices, Worklist2 inwl, int *colors) {
	int id = blockIdx.x * blockDim.x + threadIdx.x;	
	bool forbiddenColors[MAXCOLOR+1];
	int vertex;
	if (inwl.pop_id(id, vertex)) {
		int row_begin = row_offsets[vertex];
		int row_end = row_offsets[vertex + 1];
		for (int j = 0; j < MAXCOLOR; j++)
			forbiddenColors[j] = false;
		for (int offset = row_begin; offset < row_end; offset ++) {
			int neighbor = column_indices[offset];
			int color = colors[neighbor];
			if(color != MAXCOLOR)
				forbiddenColors[color] = true;
		}
		int vertex_color;
		for (vertex_color = 0; vertex_color < MAXCOLOR; vertex_color++) {
			if (!forbiddenColors[vertex_color]) {
				colors[vertex] = vertex_color;
				break;
			}
		}
		assert(vertex_color < MAXCOLOR);
	}
}

__global__ void conflict_resolve(int m, int *row_offsets, int *column_indices, Worklist2 inwl, Worklist2 outwl, int *colors) {
	//typedef cub::BlockScan<int, BLOCK_SIZE> BlockScan;
	int id = blockIdx.x * blockDim.x + threadIdx.x;
	int conflicted = 0;
	int vertex;
	if (inwl.pop_id(id, vertex)) {
		int row_begin = row_offsets[vertex];
		int row_end = row_offsets[vertex + 1];
		for (int offset = row_begin; offset < row_end; offset ++) {
			int neighbor = column_indices[offset];
			if (colors[vertex] == colors[neighbor] && vertex < neighbor) {
				conflicted = 1;
				colors[vertex] = MAXCOLOR;
				break;
			}
		}
	}
	//outwl.push_1item<BlockScan>(conflicted, vertex, BLOCK_SIZE);
	if(conflicted) outwl.push(vertex);
}

int VCSolver(int m, int nnz, int *row_offsets, int *column_indices, int *colors) {
	int num_colors = 0, iter = 0;
	int *d_row_offsets, *d_column_indices, *d_colors;
	CUDA_SAFE_CALL(cudaMalloc((void **)&d_row_offsets, (m + 1) * sizeof(int)));
	CUDA_SAFE_CALL(cudaMalloc((void **)&d_column_indices, nnz * sizeof(int)));
	CUDA_SAFE_CALL(cudaMalloc((void **)&d_colors, m * sizeof(int)));
	CUDA_SAFE_CALL(cudaMemcpy(d_row_offsets, row_offsets, (m + 1) * sizeof(int), cudaMemcpyHostToDevice));
	CUDA_SAFE_CALL(cudaMemcpy(d_column_indices, column_indices, nnz * sizeof(int), cudaMemcpyHostToDevice));
	CUDA_SAFE_CALL(cudaMemcpy(d_colors, colors, m * sizeof(int), cudaMemcpyHostToDevice));

	int nitems = m;
	Worklist2 inwl(m), outwl(m);
	Worklist2 *inwlptr = &inwl, *outwlptr = &outwl;
	for(int i = 0; i < m; i ++) inwl.h_queue[i] = i;
	inwl.set_index(m);
	CUDA_SAFE_CALL(cudaMemcpy(inwl.d_queue, inwl.h_queue, m * sizeof(int), cudaMemcpyHostToDevice));
	//thrust::sequence(thrust::device, inwl.d_queue, inwl.d_queue + m);
	CUDA_SAFE_CALL(cudaDeviceSynchronize());
	printf("Launching CUDA VC solver (%d threads/CTA) ...\n", BLOCK_SIZE);

	Timer t;
	t.Start();
	while (nitems > 0) {
		iter ++;
		int nblocks = (nitems - 1) / BLOCK_SIZE + 1;
		first_fit<<<nblocks, BLOCK_SIZE>>>(m, d_row_offsets, d_column_indices, *inwlptr, d_colors);
		conflict_resolve<<<nblocks, BLOCK_SIZE>>>(m, d_row_offsets, d_column_indices, *inwlptr, *outwlptr, d_colors);
		nitems = outwlptr->nitems();
		Worklist2 * tmp = inwlptr;
		inwlptr = outwlptr;
		outwlptr = tmp;
		outwlptr->reset();
	}
	CUDA_SAFE_CALL(cudaDeviceSynchronize());
	t.Stop();

	CUDA_SAFE_CALL(cudaMemcpy(colors, d_colors, m * sizeof(int), cudaMemcpyDeviceToHost));
	//num_colors = thrust::reduce(colors, colors + m, 0, thrust::maximum<int>()) + 1;
	//num_colors = thrust::reduce(thrust::device, d_colors, d_colors + m, 0, thrust::maximum<int>()) + 1;
	#pragma omp parallel for reduction(max : num_colors)
	for (int n = 0; n < m; n ++)
		num_colors = max(num_colors, colors[n]);
	num_colors ++;
    printf("\titerations = %d.\n", iter);
    printf("\truntime [%s] = %f ms, num_colors = %d.\n", VC_VARIANT, t.Millisecs(), num_colors);
	CUDA_SAFE_CALL(cudaFree(d_row_offsets));
	CUDA_SAFE_CALL(cudaFree(d_column_indices));
	CUDA_SAFE_CALL(cudaFree(d_colors));
	return num_colors;
}

