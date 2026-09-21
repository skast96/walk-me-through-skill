# pocket-tts server on CPU. Built by install.sh as walk-me-through-pocket.
# The model is downloaded on the first start into /root/.cache, which engine.sh mounts as a volume.
FROM python:3.12-slim
RUN pip install --no-cache-dir pocket-tts --extra-index-url https://download.pytorch.org/whl/cpu
EXPOSE 8000
CMD ["pocket-tts", "serve", "--host", "0.0.0.0", "--port", "8000"]
