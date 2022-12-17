FROM --platform=linux/amd64 ubuntu:22.04 as builder

RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential clang

COPY . /repo
WORKDIR /repo
RUN ./deps.sh
RUN make -j8
RUN clang++ /repo/mayhem/fuzz_rround.cpp -fsanitize=fuzzer,address /repo/obj/utils.o -lzip -o /fuzz

FROM ubuntu:22.04 as package
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y libcurl3-dev libzip-dev
COPY --from=builder /repo/tldr /
COPY --from=builder /fuzz /fuzz_rround
