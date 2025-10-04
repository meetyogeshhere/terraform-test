# Use a tiny base box (Alpine Linux with Nginx)
FROM nginx:alpine

# Copy your Hello World page into the box
COPY index.html /usr/share/nginx/html/index.html

# Expose port 80 (like opening a window for visitors)
EXPOSE 80

# Start the web server when the box runs
CMD ["nginx", "-g", "daemon off;"]