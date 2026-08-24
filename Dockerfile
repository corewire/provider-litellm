FROM alpine:3.22

ARG TARGETOS
ARG TARGETARCH

ADD bin/${TARGETOS}_${TARGETARCH}/provider /usr/local/bin/provider

EXPOSE 8080/tcp
USER 65532

ENTRYPOINT ["provider"]
