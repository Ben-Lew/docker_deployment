FROM public.ecr.aws/lambda/python:3.12

# Copy requirements if you have dependencies
COPY requirements.txt  .
RUN pip install -r requirements.txt

# Copy function code
COPY src/lambda_function.py ${LAMBDA_TASK_ROOT}

# Set the CMD to your handler (filename.function_name)
CMD ["lambda_function.handler"]
