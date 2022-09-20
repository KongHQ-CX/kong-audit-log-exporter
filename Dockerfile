FROM golang:1.19-alpine3.16 as builder

WORKDIR /builder
COPY . .
RUN CGO_ENABLED=0 go build -o auditlogger

#---#

FROM alpine:3.16 as runner

RUN adduser -D runner
USER runner
WORKDIR /home/runner

COPY --from=builder /builder/auditlogger /usr/local/bin/auditlogger

ENTRYPOINT [ "/usr/local/bin/auditlogger" ]
