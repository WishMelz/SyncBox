import { Transform } from 'class-transformer';
import { IsString, Length, IsOptional, IsBoolean, IsUUID, ValidateIf } from 'class-validator';
export class ConversationDto {
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @Length(1, 80)
  title!: string;
}
export class SendMessageDto {
  @IsOptional() @IsUUID() clientId?: string;
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @Length(1, 50000)
  content!: string;
}

export class SendImageDto {
  @IsOptional() @IsUUID() clientId?: string;
  @IsOptional()
  @IsString()
  @Length(0, 50000)
  content?: string;
}

export class SendAttachmentsDto extends SendImageDto {
  @IsOptional()
  @IsString()
  @Length(0, 10000)
  names?: string;
}

export class UpdateConversationDto {
  @ValidateIf((_object, value) => value !== undefined)
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @Length(1, 80)
  title?: string;
  @ValidateIf((_object, value) => value !== undefined) @IsBoolean() pinned?: boolean;
}
