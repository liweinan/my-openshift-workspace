#!/bin/bash

# Set variables
KEY_NAME="weli-rhel-key"
REGION="us-east-1"
KEY_FILE="${KEY_NAME}.pem"

echo "Processing key pair: ${KEY_NAME}"

# Check if key pair already exists
if aws ec2 describe-key-pairs --key-names "${KEY_NAME}" --region "${REGION}" >/dev/null 2>&1; then
    echo "Key pair ${KEY_NAME} already exists"
    
    # Ask user if they want to delete existing key pair
    read -p "Do you want to delete the existing key pair and recreate it? (y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting existing key pair..."
        aws ec2 delete-key-pair --key-name "${KEY_NAME}" --region "${REGION}"
        
        if [ $? -eq 0 ]; then
            echo "Key pair deleted successfully"
            
            # Delete local key file (if exists)
            if [ -f "${KEY_FILE}" ]; then
                rm -f "${KEY_FILE}"
                echo "Deleted local key file: ${KEY_FILE}"
            fi
            
            # Recreate key pair
            echo "Creating new key pair..."
            aws ec2 create-key-pair --key-name "${KEY_NAME}" --query 'KeyMaterial' --output text --region "${REGION}" > "${KEY_FILE}"
            
            if [ $? -eq 0 ]; then
                chmod 400 "${KEY_FILE}"
                echo "Key pair created successfully: ${KEY_FILE}"
            else
                echo "Key pair creation failed"
                exit 1
            fi
        else
            echo "Key pair deletion failed"
            exit 1
        fi
    else
        echo "Skipping key pair creation"
        
        # Check if local key file exists
        if [ -f "${KEY_FILE}" ]; then
            echo "Local key file exists: ${KEY_FILE}"
        else
            echo "Local key file does not exist"
            echo "Due to AWS security restrictions, existing key pair private key content cannot be downloaded"
            echo "Options:"
            echo "1. Delete existing key pair and recreate it (recommended)"
            echo "2. Use a different key pair name"
            echo "3. Manually create a new key pair"
            
            read -p "Choose action (1/2/3): " -n 1 -r
            echo
            
            case $REPLY in
                1)
                    echo "Deleting existing key pair..."
                    aws ec2 delete-key-pair --key-name "${KEY_NAME}" --region "${REGION}"
                    if [ $? -eq 0 ]; then
                        echo "Creating new key pair..."
                        aws ec2 create-key-pair --key-name "${KEY_NAME}" --query 'KeyMaterial' --output text --region "${REGION}" > "${KEY_FILE}"
                        if [ $? -eq 0 ]; then
                            chmod 400 "${KEY_FILE}"
                            echo "Key pair recreated successfully: ${KEY_FILE}"
                        else
                            echo "Key pair creation failed"
                            exit 1
                        fi
                    else
                        echo "Key pair deletion failed"
                        exit 1
                    fi
                    ;;
                2)
                    NEW_KEY_NAME="${KEY_NAME}-$(date +%s)"
                    echo "Creating key pair with new name: ${NEW_KEY_NAME}"
                    aws ec2 create-key-pair --key-name "${NEW_KEY_NAME}" --query 'KeyMaterial' --output text --region "${REGION}" > "${KEY_FILE}"
                    if [ $? -eq 0 ]; then
                        chmod 400 "${KEY_FILE}"
                        echo "New key pair created successfully: ${KEY_FILE}"
                        echo "Key pair name: ${NEW_KEY_NAME}"
                    else
                        echo "New key pair creation failed"
                        exit 1
                    fi
                    ;;
                3)
                    echo "Please handle key pair manually"
                    exit 0
                    ;;
                *)
                    echo "Invalid choice, exiting"
                    exit 1
                    ;;
            esac
        fi
    fi
else
    echo "Key pair does not exist, creating..."
    aws ec2 create-key-pair --key-name "${KEY_NAME}" --query 'KeyMaterial' --output text --region "${REGION}" > "${KEY_FILE}"
    
    if [ $? -eq 0 ]; then
        chmod 400 "${KEY_FILE}"
        echo "Key pair created successfully: ${KEY_FILE}"
    else
        echo "Key pair creation failed"
        exit 1
    fi
fi

echo "Key pair processing completed"