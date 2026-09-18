FROM golang:1.22-alpine AS build

WORKDIR /src
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 go build -o /out/go-service .

FROM gcr.io/distroless/static-debian12

COPY --from=build /out/go-service /go-service

EXPOSE 8080

ENTRYPOINT ["/go-service"]
