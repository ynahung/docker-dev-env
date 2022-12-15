FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu20.04
ENV DEBIAN_FRONTEND=noninteractive

ARG user
ARG env_name

RUN apt update; apt install -y nano wget python3-pip
RUN useradd -m ${user}

ENV PATH="/home/${user}/miniconda3/bin:${PATH}"
ARG PATH="/home/${user}/miniconda3/bin:${PATH}"

RUN mkdir -p ~/miniconda3 \
  && wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda3/miniconda.sh \
  && bash ~/miniconda3/miniconda.sh -b -u -p /home/${user}/miniconda3 \
  && rm -rf ~/miniconda3/miniconda.sh

COPY "env.yml" "/home/${user}/miniconda3/env.yml"

RUN conda update -n base -c defaults conda
RUN conda env create -f "/home/${user}/miniconda3/env.yml"
RUN conda init bash
RUN echo "export PATH=$PATH:/home/${user}/miniconda3/envs/${ENV_NAME}/bin && conda config --set auto_activate_base false && source activate ${ENV_NAME}' && cd app" >> "/home/${user}/.bashrc"
