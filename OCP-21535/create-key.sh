#!/bin/bash

# 设置变量
KEY_NAME="weli-rhel-key"
REGION="us-east-1"
KEY_FILE="${KEY_NAME}.pem"

echo "正在处理密钥对: ${KEY_NAME}"

# 检查密钥对是否已存在
if aws ec2 describe-key-pairs --key-names "${KEY_NAME}" --region "${REGION}" >/dev/null 2>&1; then
    echo "密钥对 ${KEY_NAME} 已存在"
    
    # 询问用户是否要删除现有密钥对
    read -p "是否要删除现有密钥对并重新创建? (y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "正在删除现有密钥对..."
        aws ec2 delete-key-pair --key-name "${KEY_NAME}" --region "${REGION}"
        
        if [ $? -eq 0 ]; then
            echo "密钥对删除成功"
            
            # 删除本地密钥文件（如果存在）
            if [ -f "${KEY_FILE}" ]; then
                rm -f "${KEY_FILE}"
                echo "已删除本地密钥文件: ${KEY_FILE}"
            fi
            
            # 重新创建密钥对
            echo "正在创建新的密钥对..."
            aws ec2 create-key-pair --key-name "${KEY_NAME}" --query 'KeyMaterial' --output text --region "${REGION}" > "${KEY_FILE}"
            
            if [ $? -eq 0 ]; then
                chmod 400 "${KEY_FILE}"
                echo "密钥对创建成功: ${KEY_FILE}"
            else
                echo "密钥对创建失败"
                exit 1
            fi
        else
            echo "密钥对删除失败"
            exit 1
        fi
    else
        echo "跳过密钥对创建"
        
        # 检查本地密钥文件是否存在
        if [ -f "${KEY_FILE}" ]; then
            echo "本地密钥文件已存在: ${KEY_FILE}"
        else
            echo "本地密钥文件不存在"
            echo "由于AWS安全限制，无法下载现有密钥对的私钥内容"
            echo "选项："
            echo "1. 删除现有密钥对并重新创建（推荐）"
            echo "2. 使用不同的密钥对名称"
            echo "3. 手动创建新的密钥对"
            
            read -p "选择操作 (1/2/3): " -n 1 -r
            echo
            
            case $REPLY in
                1)
                    echo "正在删除现有密钥对..."
                    aws ec2 delete-key-pair --key-name "${KEY_NAME}" --region "${REGION}"
                    if [ $? -eq 0 ]; then
                        echo "正在创建新的密钥对..."
                        aws ec2 create-key-pair --key-name "${KEY_NAME}" --query 'KeyMaterial' --output text --region "${REGION}" > "${KEY_FILE}"
                        if [ $? -eq 0 ]; then
                            chmod 400 "${KEY_FILE}"
                            echo "密钥对重新创建成功: ${KEY_FILE}"
                        else
                            echo "密钥对创建失败"
                            exit 1
                        fi
                    else
                        echo "密钥对删除失败"
                        exit 1
                    fi
                    ;;
                2)
                    NEW_KEY_NAME="${KEY_NAME}-$(date +%s)"
                    echo "使用新名称创建密钥对: ${NEW_KEY_NAME}"
                    aws ec2 create-key-pair --key-name "${NEW_KEY_NAME}" --query 'KeyMaterial' --output text --region "${REGION}" > "${KEY_FILE}"
                    if [ $? -eq 0 ]; then
                        chmod 400 "${KEY_FILE}"
                        echo "新密钥对创建成功: ${KEY_FILE}"
                        echo "密钥对名称: ${NEW_KEY_NAME}"
                    else
                        echo "新密钥对创建失败"
                        exit 1
                    fi
                    ;;
                3)
                    echo "请手动处理密钥对"
                    exit 0
                    ;;
                *)
                    echo "无效选择，退出"
                    exit 1
                    ;;
            esac
        fi
    fi
else
    echo "密钥对不存在，正在创建..."
    aws ec2 create-key-pair --key-name "${KEY_NAME}" --query 'KeyMaterial' --output text --region "${REGION}" > "${KEY_FILE}"
    
    if [ $? -eq 0 ]; then
        chmod 400 "${KEY_FILE}"
        echo "密钥对创建成功: ${KEY_FILE}"
    else
        echo "密钥对创建失败"
        exit 1
    fi
fi

echo "密钥对处理完成"
