# Stage 1: Build the Flutter web application
FROM cirrusci/flutter:latest as builder

# Set working directory
WORKDIR /app

# Copy the Flutter application files
COPY ./flutter_application /app

# Build the Flutter web application
RUN flutter build web

# Stage 2: Serve the Flutter web application with Nginx
FROM nginx:alpine

# Remove default Nginx configuration
RUN rm /etc/nginx/conf.d/default.conf

# Create a new Nginx configuration file that uses the PORT environment variable
COPY <<EOF /etc/nginx/conf.d/app.conf.template
server {
    listen       \${PORT};
    server_name  localhost;

    location / {
        root   /usr/share/nginx/html;
        index  index.html index.htm;
        try_files \$uri \$uri/ /index.html;
    }

    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }
}
EOF

# Copy the built Flutter web application from the builder stage
COPY --from=builder /app/build/web /usr/share/nginx/html

# Expose the port Nginx will listen on (this is for documentation, Cloud Run uses the PORT env var)
EXPOSE 8080

# Start Nginx and substitute the PORT environment variable in the Nginx config
CMD ["/bin/sh",  "-c",  "envsubst '\\\${\\PORT}' < /etc/nginx/conf.d/app.conf.template > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"]
