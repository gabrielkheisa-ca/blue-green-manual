from flask import Flask

app = Flask(__name__)

@app.route("/")
def hello_blue():
    return "<h1 style='color:blue'>Hello, green!</h1>"

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000)

# docker build -t gcr.io/cai-test-gke/hello-green:v1 .
# docker push gcr.io/cai-test-gke/hello-green:v1