FROM golang:1.22-alpine AS build

WORKDIR /src
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 go build -o /out/go-fixed-time-api .

FROM gcr.io/distroless/static-debian12

COPY --from=build /out/go-fixed-time-api /go-fixed-time-api

EXPOSE 8080

ENTRYPOINT ["/go-fixed-time-api"]
