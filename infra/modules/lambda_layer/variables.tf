variable "project_name" {
  description = "Project prefix used in the layer's name (e.g. flight-radar-stream)."
  type        = string
}

variable "layer_name" {
  description = "Short, lowercased name of the layer (e.g. 'python', 'python-utils'). Suffix only - the project_name is prefixed automatically."
  type        = string
}

variable "source_dir" {
  description = "Absolute path to the directory that will be zipped. For Python layers the convention is a folder containing a top-level 'python/' subdir with the dependencies inside."
  type        = string
}

variable "output_path" {
  description = "Absolute path where the zipped layer will be written by data.archive_file. Use somewhere inside .terraform/ so the file is not committed."
  type        = string
}

variable "compatible_runtimes" {
  description = "Lambda runtimes the layer is compatible with."
  type        = list(string)
  default     = ["python3.12"]
}

variable "description" {
  description = "Free-form description stored on the layer version."
  type        = string
  default     = "Shared Python dependencies (pydantic, boto3, requests, python-dotenv)."
}
