"""THROWAWAY spike client (plan Task 1). Usage: spike_client.py list | spike_client.py load <uri>"""
import socket
import sys

s = socket.create_connection(("127.0.0.1", 47820), timeout=30)
s.sendall((" ".join(sys.argv[1:]) + "\n").encode())
buf = b""
while b"\n<<END>>\n" not in buf:
    chunk = s.recv(65536)
    if not chunk:
        break
    buf += chunk
print(buf.decode().replace("\n<<END>>\n", ""))
