FROM alpine:3.22

LABEL org.opencontainers.image.title="ABESS VPN retired legacy server"
LABEL org.opencontainers.image.description="The production control plane is maintained in AbessVpn-Server-Panel."

CMD ["/bin/sh", "-c", "echo 'ABESS VPN legacy server retired. Use https://github.com/abesskamer237/AbessVpn-Server-Panel' >&2; exit 1"]
