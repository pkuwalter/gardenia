HOME=/home/cxh
CUDA_HOME=/usr/local/cuda
GARDINIA_ROOT=$(HOME)/gardinia
CC=gcc
CXX=g++
NVCC=$(CUDA_HOME)/bin/nvcc
COMPUTECAPABILITY=sm_20
CXXFLAGS += -std=c++11 -O3 -Wall
PARFLAG = -fopenmp
#NVFLAGS=-g -arch=$(COMPUTECAPABILITY) #-Xptxas -v
NVFLAGS=-w -O3 -arch=$(COMPUTECAPABILITY) #-Xptxas -v
CUB_DIR=$(HOME)/cub-1.1.1
B40_DIR=$(HOME)/back40computing-read-only
INCLUDES=-I$(CUDA_HOME)/include -I$(GARDINIA_ROOT)/include
LIBS=-L$(CUDA_HOME)/lib64
#EXTRA=-cudart shared
BIN=$(GARDINIA_ROOT)/bin
