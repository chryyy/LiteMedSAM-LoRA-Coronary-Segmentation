# 🫀 LiteMedSAM-LoRA: Parameter-Efficient 3D Coronary Artery Segmentation & Mesh Generation

[![Python 3.10+](https://img.shields.io/badge/python-3.10+-blue.svg)](https://www.python.org/downloads/)
[![PyTorch 2.x](https://img.shields.io/badge/PyTorch-2.x-EE4C2C.svg?logo=pytorch)](https://pytorch.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com)
[![Dataset](https://img.shields.io/badge/Dataset-ASOCA-informational)](https://asoca.grand-challenge.org/)

An end-to-end, lightweight deep learning pipeline for **3D Coronary Artery Segmentation** in Cardiac Computed Tomography Angiography (**CCTA**) volumes. 

This repository leverages **LiteMedSAM** (TinyViT-5M backbone) adapted via **LoRA (Low-Rank Adaptation)** under a **2.5D slicing architecture**. It features dynamic ROI zoom-cropping, asymmetric **Tversky + BCE loss**, **Test-Time Augmentation (TTA)**, morphological "sandwich" post-processing, and automated **3D printable CAD mesh export (`.stl`)** with physical voxel spacing correction.

---

## 📌 Table of Contents
- [Overview & Architecture](#-overview--architecture)
- [Key Engineering Innovations](#-key-engineering-innovations)
- [Pipeline Architecture](#-pipeline-architecture)
- [Mathematical Formulation (Loss Function)](#-mathematical-formulation-loss-function)
- [Repository Structure](#-repository-structure)
- [Installation & Setup](#-installation--setup)
- [Dataset Preparation (ASOCA)](#-dataset-preparation-asoca)
- [Training](#-training)
- [Inference & 3D Reconstruction](#-inference--3d-reconstruction)
- [Mesh Export & CAD Compatibility](#-mesh-export--cad-compatibility)
- [Model Inspection (Netron)](#-model-inspection-netron)
- [License & Acknowledgments](#-license--acknowledgments)

---

## 🔬 Overview & Architecture

Full 3D Vision Transformers for volumetric CT scans introduce extreme computational and memory footprints. Coronary arteries present an additional challenge: delicate tubular structures representing **less than 0.1% of total cardiac scan volume**, causing severe foreground-background class imbalance.

This repository implements a **2.5D Parameter-Efficient Fine-Tuning (PEFT)** approach:
1. **Backbone:** LiteMedSAM with a **TinyViT-5M** (~5M parameters) image encoder pre-trained on diverse medical imaging domains.
2. **Fine-Tuning:** **LoRA (Low-Rank Adaptation)** applied to transformer attention blocks while freezing the backbone weights, updating only the low-rank adapters, Prompt Encoder, and Mask Decoder.
3. **Dynamic Resolution Adapter:** A runtime patch applied to TinyViT's patch embedding forward pass to support a $224 \times 224$ input resolution (producing a $56 \times 56$ feature map) using pre-trained weights.

---

## 🚀 Key Engineering Innovations

| Feature | Implementation | Benefit |
| :--- | :--- | :--- |
| **2.5D Slicing Stack** | Consecutive axial slices $[Z-1, Z, Z+1]$ mapped across 3 channels | Encodes through-plane spatial context without full 3D convolution overhead |
| **Dynamic Zoom Crop** | Centered $256 \times 256$ vessel crop with random spatial jitter | Preserves millimeter-scale arterial cross-sections before the $224 \times 224$ resize |
| **PEFT Freezing** | Backbone frozen; trainable parameters limited to LoRA, decoder, and prompts | Enables training on consumer GPUs (NVIDIA T4 / 16GB VRAM) without OOM errors |
| **Asymmetric Loss** | Combined BCE + Tversky Loss ($\beta=0.7, \alpha=0.3$) | Heavily penalizes False Negatives to prevent broken vascular paths |
| **Test-Time Augmentation** | Multi-view horizontal and vertical flip soft voting | Reduces slice boundary jitter and sharpens segmentations |
| **Sandwich Cleaning** | Multi-stage filtering ($50$ px $\rightarrow$ 3D ball closing $\rightarrow$ $500$ px) | Removes stray background noise and bridges micro-discontinuities |
| **Calibrated STL Export** | Marching cubes with original physical voxel spacing correction | Generates direct 3D printable meshes ready for CAD and CFD simulations |

---

## 📐 Pipeline Architecture

```
3D Cardiac CT (.nrrd)
         │
         ▼
[ Windowing: [-200, 500] HU  ──►  Min-Max Norm [0, 1] ]
         │
         ▼
[ Dynamic 2.5D Slicing: Stack (Z-1, Z, Z+1) + 256x256 Arterial Crop ]
         │
         ▼
[ Ingestion & Prompting: Bounding Box Prompt + 224x224 Resize ]
         │
         ▼
┌────────────────────────────────────────────────────────┐
│  LiteMedSAM-LoRA (TinyViT-5M Backbone + Frozen Weights)│
│  - Prompt Encoder (Sparse BBox Embeddings)             │
│  - Mask Decoder (Two-Way Transformer)                  │
└────────────────────────────────────────────────────────┘
         │
         ▼
[ Slice-wise Inference + Test-Time Augmentation (TTA: H/V Flips) ]
         │
         ▼
[ Volumetric Reassembly & Inverse Coordinate Mapping ]
         │
         ▼
[ Sandwich Cleaning: Area Filter (50 px) ──► Ball(2) Closing ──► Area Filter (500 px) ]
         │
         ▼
[ Marching Cubes with Real Physical Spacing ] ──► [ 3D STL Mesh Output ]
```

---

## 🧮 Mathematical Formulation (Loss Function)

To counter severe foreground-background imbalance, the optimization function combines Binary Cross-Entropy ($\mathcal{L}_{\text{BCE}}$) with an asymmetric **Tversky Loss** ($\mathcal{L}_{\text{Tversky}}$):

$$\mathcal{L}_{\text{total}} = 0.5 \cdot \mathcal{L}_{\text{BCE}} + 0.5 \cdot \mathcal{L}_{\text{Tversky}}$$

The Tversky index prioritizes vessel recall by setting $\beta > \alpha$:

$$\mathcal{L}_{\text{Tversky}} = 1 - \frac{\sum_{i=1}^N p_i g_i + \epsilon}{\sum_{i=1}^N p_i g_i + \alpha \sum_{i=1}^N p_i (1 - g_i) + \beta \sum_{i=1}^N (1 - p_i) g_i + \epsilon}$$

Where:
- $p_i \in [0, 1]$ is the predicted sigmoid probability.
- $g_i \in \{0, 1\}$ is the ground truth binary label.
- $\alpha = 0.3$ penalizes False Positives.
- $\beta = 0.7$ penalizes False Negatives (critical for preserving distal vessel branches).
- $\epsilon = 10^{-5}$ provides numerical stability.

---

## 📂 Repository Structure

```plaintext
LiteMedSAM-LoRA-Coronary-Segmentation/
├── configs/
│   └── config.py               # Dataset paths, seed, splits, and training parameters
├── data/
│   ├── dataset.py              # 2.5D slicing, dynamic ROI zooming, and augmentations
│   └── utils.py                # Intensity clipping (-200 to 500 HU) and NRRD loaders
├── models/
│   ├── litemedsam.py           # MedSAM_Lite wrapper (TinyViT + Prompt Encoder + Decoder)
│   ├── dynamic_patch.py        # Forward feature monkey patch for 224x224 grid fix
│   └── export_netron.py        # TorchScript 256x256 model generator for Netron
├── postprocessing/
│   ├── morphological.py        # Sandwich cleaning (remove small objects + ball closing)
│   └── mesh_export.py          # Marching cubes surface extraction and STL exporter
├── train.py                    # Training loop with step scheduler and validation
├── inference.py                # Full-volume 3D inference engine with TTA
├── requirements.txt            # Python dependencies
└── README.md                   # Project documentation
```

---

## 🛠️ Installation & Setup

### 1. Clone the Repository
```bash
git clone [https://github.com/your-username/LiteMedSAM-LoRA-Coronary-Segmentation.git](https://github.com/your-username/LiteMedSAM-LoRA-Coronary-Segmentation.git)
cd LiteMedSAM-LoRA-Coronary-Segmentation
```

### 2. Environment Setup
Recommended Python environment: `>= 3.10` with CUDA acceleration.
```bash
conda create -n litemedsam python=3.10 -y
conda activate litemedsam

# Install PyTorch matching your CUDA version
pip install torch torchvision --index-url [https://download.pytorch.org/whl/cu118](https://download.pytorch.org/whl/cu118)

# Install dependencies
pip install -r requirements.txt
```

*Requirements (`requirements.txt`):*
```text
numpy
torch
torchvision
SimpleITK
opencv-python
matplotlib
scikit-image
numpy-stl
plotly
git+[https://github.com/facebookresearch/segment-anything.git](https://github.com/facebookresearch/segment-anything.git)
```

### 3. Base Model Weights
Download the official LiteMedSAM base checkpoint (`lite_medsam.pth`) and place it inside the `checkpoints/` directory:
```bash
mkdir -p checkpoints/
# Place lite_medsam.pth inside checkpoints/
```

---

## 🩻 Dataset Preparation (ASOCA)

This implementation is configured for the **Automated Segmentation of Coronary Arteries (ASOCA)** dataset (`.nrrd` format):

```plaintext
DATASET_ASOCA/
├── Normal/
│   ├── CTCA/          # Patient CT scans (.nrrd)
│   └── Annotations/   # Ground truth binary masks (.nrrd)
└── Diseased/
    ├── CTCA/
    └── Annotations/
```

CT volumes are windowed between `[-200, 500]` Hounsfield Units (HU) to maximize contrast in iodinated lumens against surrounding cardiac structures.

---

## 🏋️ Training

Launch LoRA fine-tuning using AdamW and the asymmetric Tversky loss:

```bash
python train.py \
  --data_path /path/to/DATASET_ASOCA \
  --base_weights checkpoints/lite_medsam.pth \
  --batch_size 4 \
  --lr 1e-4 \
  --max_steps 1000 \
  --eval_interval 100 \
  --save_dir checkpoints/
```

Key training defaults:
- **Optimizer:** `AdamW` ($\text{weight\_decay}=0.05$)
- **Gradient Clipping:** `max_norm = 1.0`
- **Dynamic Cropping:** $256 \times 256$ ROI centered on vessel with $\pm 20\text{px}$ random spatial jitter
- **Geometric Augmentations:** Random Horizontal/Vertical Flips ($p=0.5$) and 90° Rotations

---

## 🔮 Inference & 3D Reconstruction

Full-volume inference slices the volume axially, runs predictions with **Test-Time Augmentation (TTA)**, and reconstructs the full 3D prediction matrix:

```python
from models.litemedsam import build_litemedsam_224
from inference import run_full_volume_inference

model = build_litemedsam_224("checkpoints/LiteMedSAM_best.pth", device="cuda")
gt_mask, pred_mask = run_full_volume_inference(
    model, 
    nrrd_path="data/patient_01.nrrd", 
    crop_size=256,
    use_tta=True
)
```

To run 3D volumetric validation with interactive Plotly mesh visualization:

```bash
python inference.py --input data/patient_01.nrrd --weights checkpoints/LiteMedSAM_best.pth --visualize
```

---

## 🖨️ Mesh Export & CAD Compatibility

To generate `.stl` meshes ready for 3D printing or computational fluid dynamics (CFD):

1. **Morphological Sandwich Filtering:**
   - Small object suppression ($< 50$ voxels)
   - Binary closing with a 3D spherical structuring element (`ball(2)`)
   - Final spurious connected-component removal ($< 500$ voxels)
2. **Spacing Calibration:**
   Extracts physical voxel spacing from headers (`spacing = sitk_img.GetSpacing()`) to guarantee 1:1 scale:

```bash
python postprocessing/mesh_export.py \
  --input_nrrd data/patient_01.nrrd \
  --weights checkpoints/LiteMedSAM_best.pth \
  --output_dir ./stl_exports/
```

---

## 🔍 Model Inspection (Netron)

Because of dynamic feature reshaping in the patched ViT at $224 \times 224$, standard graph tracing can fail in generic visualizers.

We provide a script to trace a structurally identical $256 \times 256$ TorchScript model (`litemedsam_netron_structure.pt`):

```bash
python models/export_netron.py --output checkpoints/litemedsam_netron_structure.pt
```

Upload the output file to [Netron](https://netron.app) to inspect layers, LoRA insertion points, and tensor shapes.

---

## 📄 License & Acknowledgments

- **License:** MIT License.
- **Foundational Models:** Based on [MedSAM](https://github.com/bowang-lab/MedSAM) and [LiteMedSAM-LoRA](https://github.com/lseventeen/LiteMedSAM-LoRA).
- **Challenge Data:** Coronary artery datasets provided by the [ASOCA Challenge](https://asoca.grand-challenge.org/).
